"""
Model Competition — collect 150 API responses (5 models × 30 prompts).

Usage:
    python tools/model_competition.py [style]

    style: freestyle (default), origami, balloon, etc.

Saves results to tools/competition_data/{style}/{category}_{index:02d}_{model}.json
Resumes from where it left off (skips existing files).
"""

import asyncio
import json
import os
import sys
import time

try:
    import aiohttp
except ImportError:
    print("Installing aiohttp...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "aiohttp"])
    import aiohttp

API_URL = "https://origami-server.fly.dev/api/generate"
API_KEY = "f75898d3ab723052d2bb696f5f01d507"

# New models to collect — existing data (gpt54_nano, gpt54_mini, gpt_mini, etc.) already on disk
MODELS = ["flash25_lite", "flash25", "gemini25_pro"]

# Expensive models only run prompts 1, 5, 10 per category (indices 0,4,9,10,14,19,20,24,29)
EXPENSIVE_MODELS = {"opus", "gpt54_pro"}
EXPENSIVE_INDICES = {0, 4, 9, 10, 14, 19, 20, 24, 29}

PROMPTS = [
    # Creatures (0-9)
    {"prompt": "jellyfish", "category": "creature"},
    {"prompt": "red fox", "category": "creature"},
    {"prompt": "dragon with wings", "category": "creature"},
    {"prompt": "purple octopus with big eyes", "category": "creature"},
    {"prompt": "robot dog with laser eyes and metal tail", "category": "creature"},
    {"prompt": "ice phoenix with crystal feathers and glowing blue eyes", "category": "creature"},
    {"prompt": "three-headed snake with armor scales and a forked tail on each head", "category": "creature"},
    {"prompt": "steampunk owl with brass goggles, clockwork wings, and a top hat", "category": "creature"},
    {"prompt": "rainbow unicorn with butterfly wings, a spiral horn, and flowers in its mane", "category": "creature"},
    {"prompt": "a pink jellyfish wearing a golden crown with slippers on each tentacle", "category": "creature"},
    # Props (10-19)
    {"prompt": "mushroom", "category": "prop"},
    {"prompt": "treasure chest", "category": "prop"},
    {"prompt": "campfire with logs", "category": "prop"},
    {"prompt": "crystal ball on a wooden stand", "category": "prop"},
    {"prompt": "birdhouse with a tiny bird perched on top", "category": "prop"},
    {"prompt": "enchanted lantern with floating flames and ivy wrapped around it", "category": "prop"},
    {"prompt": "ancient stone fountain with three tiers and water flowing down", "category": "prop"},
    {"prompt": "haunted grandfather clock with a cracked face and ghostly green glow", "category": "prop"},
    {"prompt": "wizard's desk with stacked books, a candle, a quill, and a bubbling potion", "category": "prop"},
    {"prompt": "a giant snow globe with a tiny village, houses, trees, and falling snowflakes", "category": "prop"},
    # Vehicles (20-29)
    {"prompt": "car", "category": "vehicle"},
    {"prompt": "red truck", "category": "vehicle"},
    {"prompt": "yellow taxi with a roof sign", "category": "vehicle"},
    {"prompt": "blue race car with a spoiler and stripes", "category": "vehicle"},
    {"prompt": "flying carpet with tassels and gold trim", "category": "vehicle"},
    {"prompt": "pirate ship with three sails and a skull flag", "category": "vehicle"},
    {"prompt": "steam locomotive with smoke stack, coal car, and brass fittings", "category": "vehicle"},
    {"prompt": "futuristic hover bike with neon lights, chrome body, and jet exhaust", "category": "vehicle"},
    {"prompt": "dragon-shaped boat with wings for sails and a serpent figurehead", "category": "vehicle"},
    {"prompt": "a giant rubber duck boat with a captain's hat and spinning propeller tail", "category": "vehicle"},
]

STYLE = sys.argv[1] if len(sys.argv) > 1 else "freestyle"
OUT_DIR = os.path.join(os.path.dirname(__file__), "competition_data", STYLE)
DELAY_BETWEEN_CALLS = 2.5  # seconds, above 2s burst limit
MAX_RETRIES = 3


def file_path(category: str, index: int, model: str) -> str:
    return os.path.join(OUT_DIR, f"{category}_{index:02d}_{model}.json")


async def call_api(session: aiohttp.ClientSession, prompt_info: dict, model: str, prompt_index: int) -> dict | None:
    """Call the API with retries. Returns the model data dict or None."""
    payload = {
        "prompt": prompt_info["prompt"],
        "player_id": f"comp_{STYLE}_{model}",
        "category": prompt_info["category"],
        "style": STYLE,
        "model": model,
        "dm_mode": True,
    }
    headers = {"Content-Type": "application/json", "X-Api-Key": API_KEY}

    for attempt in range(MAX_RETRIES):
        try:
            async with session.post(API_URL, json=payload, headers=headers, timeout=aiohttp.ClientTimeout(total=60)) as resp:
                data = await resp.json()
                if resp.status == 200 and data.get("success"):
                    return data.get("model")
                else:
                    error = data.get("error") or data.get("detail") or f"HTTP {resp.status}"
                    print(f"  FAIL [{model}] prompt {prompt_index} ({prompt_info['prompt'][:30]}): {error}")
                    if attempt < MAX_RETRIES - 1:
                        wait = 3 * (2 ** attempt)
                        print(f"    Retrying in {wait}s...")
                        await asyncio.sleep(wait)
        except Exception as e:
            print(f"  ERROR [{model}] prompt {prompt_index}: {e}")
            if attempt < MAX_RETRIES - 1:
                wait = 3 * (2 ** attempt)
                print(f"    Retrying in {wait}s...")
                await asyncio.sleep(wait)

    return None


async def collect_for_model(session: aiohttp.ClientSession, model: str, progress: dict):
    """Collect all 30 prompts for one model sequentially."""
    for i, prompt_info in enumerate(PROMPTS):
        # Skip non-selected prompts for expensive models
        if model in EXPENSIVE_MODELS and i not in EXPENSIVE_INDICES:
            continue

        fp = file_path(prompt_info["category"], i, model)
        if os.path.exists(fp):
            progress["done"] += 1
            progress["skipped"] += 1
            continue

        result = await call_api(session, prompt_info, model, i)

        if result:
            with open(fp, "w") as f:
                json.dump(result, f, indent=2)
            progress["done"] += 1
            progress["success"] += 1
        else:
            # Save failure marker
            with open(fp, "w") as f:
                json.dump({"_failed": True, "prompt": prompt_info["prompt"], "model": model}, f)
            progress["done"] += 1
            progress["failed"] += 1

        total = len(PROMPTS) * len(MODELS)
        print(f"  [{progress['done']}/{total}] {model}: {prompt_info['category']} #{i % 10 + 1} "
              f"({prompt_info['prompt'][:40]}) — {'OK' if result else 'FAILED'}")

        # Rate limit delay — Google models need more spacing to avoid 429s
        if i < len(PROMPTS) - 1:
            delay = 8.0 if model in ("flash3", "gemini_pro") else DELAY_BETWEEN_CALLS
            await asyncio.sleep(delay)


async def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    total = len(PROMPTS) * len(MODELS)
    print(f"Model Competition: {len(PROMPTS)} prompts × {len(MODELS)} models = {total} calls")
    print(f"Models: {', '.join(MODELS)}")
    print(f"Output: {OUT_DIR}")
    print()

    progress = {"done": 0, "success": 0, "failed": 0, "skipped": 0}

    start = time.time()
    async with aiohttp.ClientSession() as session:
        # Run all 5 models in parallel
        tasks = [collect_for_model(session, model, progress) for model in MODELS]
        await asyncio.gather(*tasks)

    elapsed = time.time() - start
    print(f"\nDone in {elapsed:.1f}s!")
    print(f"  Success: {progress['success']}")
    print(f"  Failed:  {progress['failed']}")
    print(f"  Skipped: {progress['skipped']} (already existed)")

    # Write index file
    index = []
    for i, prompt_info in enumerate(PROMPTS):
        for model in MODELS:
            fp = file_path(prompt_info["category"], i, model)
            if os.path.exists(fp):
                with open(fp) as f:
                    data = json.load(f)
                index.append({
                    "prompt_index": i,
                    "prompt": prompt_info["prompt"],
                    "category": prompt_info["category"],
                    "model": model,
                    "success": "_failed" not in data,
                    "file": os.path.basename(fp),
                    "parts": len(data.get("parts", [])) if "_failed" not in data else 0,
                })

    with open(os.path.join(OUT_DIR, "index.json"), "w") as f:
        json.dump(index, f, indent=2)
    print(f"  Index written: {len(index)} entries")


if __name__ == "__main__":
    asyncio.run(main())
