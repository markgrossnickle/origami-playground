"""
Collect the same 60 models but with the updated prompt (no "origami" prefix).
Saves to tools/demo_showcase_v2/ to keep separate from originals.
"""
import asyncio, aiohttp, json, os, time

API_URL = "https://origami-server.fly.dev"
API_KEY = "f75898d3ab723052d2bb696f5f01d507"

MODELS = ["flash25_lite", "flash_lite", "flash25", "flash3"]
DISPLAY = {
    "flash25_lite": "FL 2.5 Lite",
    "flash_lite": "FL 3.1 Lite",
    "flash25": "Gem 2.5 Flash",
    "flash3": "Gem 3 Flash",
}

PROMPTS = [
    ("creature", "a tiny round hedgehog with big curious eyes"),
    ("creature", "a three-headed serpent coiled around itself"),
    ("creature", "a massive armored rhino beetle standing upright"),
    ("creature", "a ghostly jellyfish trailing long glowing tentacles"),
    ("creature", "a baby phoenix with smoldering feathers and a long tail"),
    ("vehicle", "a flying carpet with tassels and cushions"),
    ("vehicle", "a steampunk motorcycle with oversized exhaust pipes"),
    ("vehicle", "a submarine shaped like a hammerhead shark"),
    ("vehicle", "a hovering food truck selling tacos"),
    ("vehicle", "a giant snail with a saddle on its shell"),
    ("prop", "an ancient treasure chest overflowing with gold coins"),
    ("prop", "a magical bookshelf with floating glowing books"),
    ("prop", "a campfire with roasting marshmallows on sticks"),
    ("prop", "a broken robot slumped against a wall sparking"),
    ("prop", "a giant mushroom house with a tiny door and windows"),
]

OUT_DIR = os.path.join(os.path.dirname(__file__), "demo_showcase_v2")
os.makedirs(OUT_DIR, exist_ok=True)


async def generate(session, prompt_idx, category, prompt, model, sem):
    fname = os.path.join(OUT_DIR, f"{category}_{prompt_idx:02d}_{model}.json")
    if os.path.exists(fname):
        try:
            with open(fname) as f:
                d = json.load(f)
            if d.get("parts"):
                return "skip"
        except:
            pass

    async with sem:
        payload = {
            "prompt": prompt,
            "player_id": f"demov2_{model}_{prompt_idx}",
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
                        original_name = model_data.get("name", prompt[:20])
                        model_data["name"] = f"{original_name} ({DISPLAY[model]})"
                        with open(fname, "w") as f:
                            json.dump(model_data, f, indent=2)
                        parts = len(model_data.get("parts", []))
                        print(f"  OK  {model:15s} {category:8s} #{prompt_idx:02d} ({parts} parts)")
                        return "ok"
                    else:
                        err = data.get("error", "unknown")
                        print(f"  ERR {model:15s} {category:8s} #{prompt_idx:02d} attempt {attempt+1}: {err}")
                        if attempt < 2:
                            await asyncio.sleep(5 * (attempt + 1))
            except Exception as e:
                print(f"  EXC {model:15s} {category:8s} #{prompt_idx:02d} attempt {attempt+1}: {e}")
                if attempt < 2:
                    await asyncio.sleep(5 * (attempt + 1))
        return "fail"


async def main():
    total = len(PROMPTS) * len(MODELS)
    print(f"Generating {total} showcase v2 models (no origami prefix)...")
    start = time.time()

    sem = asyncio.Semaphore(4)
    async with aiohttp.ClientSession() as session:
        tasks = []
        for prompt_idx, (category, prompt) in enumerate(PROMPTS):
            for model in MODELS:
                tasks.append(generate(session, prompt_idx, category, prompt, model, sem))

        results = await asyncio.gather(*tasks)

    ok = sum(1 for r in results if r == "ok")
    skip = sum(1 for r in results if r == "skip")
    fail = sum(1 for r in results if r == "fail")
    elapsed = time.time() - start
    print(f"\nDone in {elapsed:.1f}s! Success: {ok}, Skipped: {skip}, Failed: {fail}")


asyncio.run(main())
