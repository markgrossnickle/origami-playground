"""
Generate a comparison grid: 3 Gemini models x diverse prompts.
Each model creates every prompt for side-by-side comparison.
"""
import asyncio, aiohttp, json, os, time

API_URL = "https://origami-server.fly.dev"
API_KEY = "f75898d3ab723052d2bb696f5f01d507"

MODELS = ["flash25_lite", "flash3", "gemini_pro"]
DISPLAY = {
    "flash25_lite": "FL 2.5 Lite (~$0.001)",
    "flash3": "Gem 3 Flash (~$0.05)",
    "gemini_pro": "Gem 3.1 Pro (~$0.20)",
}

PROMPTS = [
    # Creatures - diverse shapes
    ("creature", "a giant octopus with eight curling tentacles and glowing eyes"),
    ("creature", "a perfectly round pufferfish puffed up with tiny spines all over"),
    ("creature", "an enormous sandworm bursting out of the ground, long segmented body"),
    ("creature", "a majestic eagle mid-flight with outstretched wings and talons"),
    ("creature", "a crystal golem made entirely of jagged translucent shards"),
    ("creature", "a tiny ladybug with spotted shell and delicate antennae"),
    ("creature", "a long Chinese dragon snaking through the air with whiskers and horns"),
    # Vehicles - variety
    ("vehicle", "a pirate ship with sails and cannons"),
    ("vehicle", "a futuristic hoverbike with glowing engine pods"),
    ("vehicle", "a hot air balloon with a wicker basket and colorful panels"),
    ("vehicle", "a chunky monster truck with oversized wheels"),
    ("vehicle", "a wooden rowboat with oars"),
    # Props - variety
    ("prop", "a bubbling cauldron with green potion overflowing"),
    ("prop", "a grandfather clock with a swinging pendulum"),
    ("prop", "a giant crystal ball on an ornate stand, glowing from within"),
    ("prop", "a medieval catapult loaded with a boulder"),
    ("prop", "a cozy campfire with a pot hanging over it on a tripod"),
    # Tools - displayed as props (floating, not equipped)
    ("prop", "a glowing enchanted blade with a jeweled crossguard"),
    ("prop", "a wizard staff with a spiraling crystal at the top"),
    ("prop", "a golden trident crackling with energy"),
    ("prop", "a massive war hammer with runes etched into the head"),
]

OUT_DIR = os.path.join(os.path.dirname(__file__), "demo_grid")
os.makedirs(OUT_DIR, exist_ok=True)


async def generate(session, prompt_idx, category, prompt, model, sem):
    fname = os.path.join(OUT_DIR, f"{prompt_idx:02d}_{model}.json")
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
            "player_id": f"grid_{model}_{prompt_idx}",
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
                        # Clean name: strip "Origami" and append model display
                        name = model_data.get("name", prompt[:20])
                        name = name.replace("Origami ", "").replace("origami ", "")
                        model_data["name"] = f"{name} ({DISPLAY[model].split('(')[0].strip()})"
                        with open(fname, "w") as f:
                            json.dump(model_data, f, indent=2)
                        parts = len(model_data.get("parts", []))
                        print(f"  OK  {model:15s} #{prompt_idx:02d} ({parts:2d} parts) - {prompt[:45]}")
                        return "ok"
                    else:
                        err = data.get("error", "unknown")
                        print(f"  ERR {model:15s} #{prompt_idx:02d} attempt {attempt+1}: {err}")
                        if attempt < 2:
                            await asyncio.sleep(5 * (attempt + 1))
            except Exception as e:
                print(f"  EXC {model:15s} #{prompt_idx:02d} attempt {attempt+1}: {e}")
                if attempt < 2:
                    await asyncio.sleep(5 * (attempt + 1))
        return "fail"


async def main():
    total = len(PROMPTS) * len(MODELS)
    print(f"Generating {total} models ({len(PROMPTS)} prompts x {len(MODELS)} models)...")
    print(f"Models: {', '.join(DISPLAY.values())}")
    print()
    start = time.time()

    sem = asyncio.Semaphore(3)  # one per model
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
