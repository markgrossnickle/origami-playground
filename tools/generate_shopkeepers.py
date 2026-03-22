"""
Generate shopkeeper creatures and display models for the 3 shops.
Uses the origami-server API to create creatures, then outputs ShopkeeperData.luau.
"""
import asyncio, aiohttp, json, os, sys

API_URL = "https://origami-server.fly.dev"
API_KEY = "f75898d3ab723052d2bb696f5f01d507"

SCRIPT_DIR = os.path.dirname(__file__)
OUT_DIR = os.path.join(SCRIPT_DIR, "shopkeeper_data")
LUAU_OUT = os.path.join(SCRIPT_DIR, "..", "src", "ReplicatedStorage", "Shared", "ShopkeeperData.luau")

os.makedirs(OUT_DIR, exist_ok=True)

# --- Shopkeeper definitions ---

SHOPKEEPERS = [
    {
        "id": "pawn_shop",
        "name": "The Pawn Shop",
        "shopkeeperName": "Patches the Packrat",
        "prompt": "a round friendly packrat with big eyes sitting on a pile of gold trinkets",
        "category": "creature",
        "model": "gemini_pro",
        "speechText": "Welcome! Browse my collection\\nof blueprints - pay with Folds!",
        "promptText": "Browse Blueprints",
        "shopType": "browse",
        "lockedModel": "",
        "position": [-30, 3, -20],
    },
    {
        "id": "workshop",
        "name": "The Workshop",
        "shopkeeperName": "Inky the Paper Crane",
        "prompt": "a large paper crane bird with ink-stained wings holding a quill pen",
        "category": "creature",
        "model": "gemini_pro",
        "speechText": "Bring me Paper Tokens and\\nI'll fold something new for you!",
        "promptText": "Create",
        "shopType": "create_lite",
        "lockedModel": "flash25_lite",
        "position": [0, 3, -20],
    },
    {
        "id": "atelier",
        "name": "The Atelier",
        "shopkeeperName": "Prism the Crystal Fox",
        "prompt": "an elegant crystalline fox with gem-like purple and gold fur, regal pose",
        "category": "creature",
        "model": "gemini_pro",
        "speechText": "Only the finest creations here.\\nPremium quality, premium results.",
        "promptText": "Create Premium",
        "shopType": "create_pro",
        "lockedModel": "gemini_pro",
        "position": [30, 3, -20],
    },
]

# --- Display creatures near each shop ---

DISPLAY_MODELS = [
    # Pawn shop area - variety of pre-built models
    {"shop": "pawn_shop", "prompt": "a treasure chest overflowing with gold coins", "category": "prop", "model": "flash25_lite", "offset": [-8, 0, 5]},
    {"shop": "pawn_shop", "prompt": "a dusty antique globe on a wooden stand", "category": "prop", "model": "flash25_lite", "offset": [8, 0, 5]},
    {"shop": "pawn_shop", "prompt": "a friendly orange tabby cat sitting down", "category": "creature", "model": "flash25_lite", "offset": [-5, 0, -8]},

    # Workshop area - FL 2.5 Lite showcase
    {"shop": "workshop", "prompt": "a colorful parrot perched on a branch", "category": "creature", "model": "flash25_lite", "offset": [-8, 0, 5]},
    {"shop": "workshop", "prompt": "a miniature windmill with spinning blades", "category": "prop", "model": "flash25_lite", "offset": [8, 0, 5]},
    {"shop": "workshop", "prompt": "a cute round hedgehog with tiny legs", "category": "creature", "model": "flash25_lite", "offset": [0, 0, 8]},

    # Atelier area - Gem 3.1 Pro showcase
    {"shop": "atelier", "prompt": "a majestic phoenix with fiery wings and flowing tail", "category": "creature", "model": "gemini_pro", "offset": [-8, 0, 5]},
    {"shop": "atelier", "prompt": "an ornate crystal chandelier with glowing candles", "category": "prop", "model": "gemini_pro", "offset": [8, 0, 5]},
    {"shop": "atelier", "prompt": "a regal lion with a flowing golden mane", "category": "creature", "model": "gemini_pro", "offset": [0, 0, 8]},
]


async def generate_one(session, prompt, category, model, fname, label):
    """Generate a single model via the API."""
    if os.path.exists(fname):
        try:
            with open(fname) as f:
                d = json.load(f)
            if d.get("parts"):
                print(f"  SKIP {label}")
                return d
        except:
            pass

    payload = {
        "prompt": prompt,
        "player_id": f"shopkeeper_{label}",
        "category": category,
        "style": "freestyle",
        "model": model,
        "dm_mode": True,
    }

    for attempt in range(3):
        try:
            async with session.post(
                f"{API_URL}/api/generate",
                json=payload,
                headers={"X-Api-Key": API_KEY},
                timeout=aiohttp.ClientTimeout(total=120),
            ) as resp:
                data = await resp.json()
                if data.get("success") and data.get("model"):
                    model_data = data["model"]
                    # Clean name
                    name = model_data.get("name", prompt[:30])
                    name = name.replace("Origami ", "").replace("origami ", "")
                    model_data["name"] = name
                    with open(fname, "w") as f:
                        json.dump(model_data, f, indent=2)
                    parts = len(model_data.get("parts", []))
                    print(f"  OK   {label} ({parts} parts)")
                    return model_data
                else:
                    err = data.get("error", "unknown")
                    print(f"  ERR  {label} attempt {attempt+1}: {err}")
                    if attempt < 2:
                        await asyncio.sleep(5 * (attempt + 1))
        except Exception as e:
            print(f"  EXC  {label} attempt {attempt+1}: {e}")
            if attempt < 2:
                await asyncio.sleep(5 * (attempt + 1))

    print(f"  FAIL {label}")
    return None


def lua_string(s):
    s = s.encode("ascii", "replace").decode("ascii")
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_value(v, indent=1):
    tabs = "\t" * indent
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return lua_string(v)
    if isinstance(v, list):
        if all(isinstance(x, (int, float)) for x in v):
            return "{ " + ", ".join(str(x) for x in v) + " }"
        items = []
        for item in v:
            items.append(f"{tabs}\t{lua_value(item, indent + 1)},")
        return "{\n" + "\n".join(items) + f"\n{tabs}}}"
    if isinstance(v, dict):
        items = []
        for k, val in v.items():
            key_str = k if k.isidentifier() else f'["{k}"]'
            items.append(f"{tabs}\t{key_str} = {lua_value(val, indent + 1)},")
        return "{\n" + "\n".join(items) + f"\n{tabs}}}"
    return str(v)


def generate_luau(shopkeepers_data, display_data):
    """Generate ShopkeeperData.luau from collected data."""
    lines = []
    lines.append("-- AUTO-GENERATED by generate_shopkeepers.py - do not edit by hand")
    lines.append("local ShopkeeperData = {}\n")

    lines.append("ShopkeeperData.SHOPS = {")
    for shop in SHOPKEEPERS:
        model_data = shopkeepers_data.get(shop["id"])
        if not model_data:
            print(f"  WARNING: No model data for {shop['id']}, using placeholder")
            continue

        lines.append(f"\t{{")
        lines.append(f"\t\tid = {lua_string(shop['id'])},")
        lines.append(f"\t\tname = {lua_string(shop['name'])},")
        lines.append(f"\t\tshopkeeperName = {lua_string(shop['shopkeeperName'])},")
        lines.append(f"\t\tspeechText = {lua_string(shop['speechText'])},")
        lines.append(f"\t\tpromptText = {lua_string(shop['promptText'])},")
        lines.append(f"\t\tshopType = {lua_string(shop['shopType'])},")
        lines.append(f"\t\tlockedModel = {lua_string(shop['lockedModel'])},")
        lines.append(f"\t\tposition = {{ {shop['position'][0]}, {shop['position'][1]}, {shop['position'][2]} }},")
        lines.append(f"\t\tmodelData = {lua_value(model_data, 2)},")
        lines.append(f"\t}},")

    lines.append("}\n")

    # Display models grouped by shop
    lines.append("ShopkeeperData.DISPLAY_MODELS = {")
    for dm in DISPLAY_MODELS:
        key = f"{dm['shop']}_{dm['prompt'][:20].replace(' ', '_')}"
        model_data = display_data.get(key)
        if not model_data:
            continue
        shop_pos = next(s["position"] for s in SHOPKEEPERS if s["id"] == dm["shop"])
        world_pos = [shop_pos[0] + dm["offset"][0], shop_pos[1] + dm["offset"][1], shop_pos[2] + dm["offset"][2]]
        lines.append(f"\t{{")
        lines.append(f"\t\tshop = {lua_string(dm['shop'])},")
        lines.append(f"\t\tposition = {{ {world_pos[0]}, {world_pos[1]}, {world_pos[2]} }},")
        lines.append(f"\t\tmodelData = {lua_value(model_data, 2)},")
        lines.append(f"\t}},")
    lines.append("}\n")

    lines.append("return ShopkeeperData")

    content = "\n".join(lines) + "\n"
    with open(LUAU_OUT, "w", newline="\n") as f:
        f.write(content)
    size = os.path.getsize(LUAU_OUT)
    print(f"\nGenerated: {LUAU_OUT}")
    print(f"  File size: {size:,} bytes")


async def main():
    print("=== Generating Shopkeepers ===\n")

    shopkeepers_data = {}
    display_data = {}

    async with aiohttp.ClientSession() as session:
        # Generate shopkeepers (sequential to avoid rate limits on gemini_pro)
        for shop in SHOPKEEPERS:
            fname = os.path.join(OUT_DIR, f"{shop['id']}.json")
            result = await generate_one(
                session, shop["prompt"], shop["category"], shop["model"],
                fname, shop["shopkeeperName"]
            )
            if result:
                shopkeepers_data[shop["id"]] = result

        print(f"\nShopkeepers: {len(shopkeepers_data)}/3\n")
        print("=== Generating Display Models ===\n")

        # Generate display models (can be parallel within same model type)
        sem = asyncio.Semaphore(2)
        async def gen_display(dm):
            key = f"{dm['shop']}_{dm['prompt'][:20].replace(' ', '_')}"
            fname = os.path.join(OUT_DIR, f"display_{key[:40]}.json")
            async with sem:
                result = await generate_one(
                    session, dm["prompt"], dm["category"], dm["model"],
                    fname, f"{dm['shop']}/{dm['prompt'][:30]}"
                )
                if result:
                    display_data[key] = result

        tasks = [gen_display(dm) for dm in DISPLAY_MODELS]
        await asyncio.gather(*tasks)

        print(f"\nDisplay models: {len(display_data)}/{len(DISPLAY_MODELS)}")

    # Generate Luau output
    print("\n=== Generating ShopkeeperData.luau ===\n")
    generate_luau(shopkeepers_data, display_data)


if __name__ == "__main__":
    asyncio.run(main())
