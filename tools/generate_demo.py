"""
Generate demo models: a variety of creatures and vehicles using Opus 4.6.
Calls the origami-server API and saves JSON files for conversion to Luau.
"""
import asyncio, aiohttp, json, os, time

API_URL = "https://origami-server.fly.dev"
API_KEY = "f75898d3ab723052d2bb696f5f01d507"

MODEL = "gemini_pro"

PROMPTS = [
    # Creatures - diverse and visually impressive
    ("creature", "a majestic phoenix with fiery wings spread wide, trailing embers"),
    ("creature", "a tiny mechanical clockwork spider with brass gears and ruby eyes"),
    ("creature", "a massive armored turtle with a miniature castle on its shell"),
    ("creature", "a ghostly jellyfish that glows neon blue and trails long luminous tentacles"),
    ("creature", "a fluffy three-tailed fox with aurora-colored fur"),
    ("creature", "a stone gargoyle perched with wings folded, glowing cracks in its body"),
    # Vehicles - fun variety
    ("vehicle", "a steampunk airship with propellers, brass hull, and observation deck"),
    ("vehicle", "a dragon-shaped roller coaster car with flame decals"),
    ("vehicle", "a sleek neon-lit motorcycle with transparent wheels"),
    ("vehicle", "a flying carpet with tassels and intricate golden patterns"),
    # Props - eye-catching demo pieces
    ("prop", "a massive enchanted tree with glowing fruit and a door in its trunk"),
    ("prop", "an ancient stone portal with swirling purple energy in its center"),
]

OUT_DIR = os.path.join(os.path.dirname(__file__), "demo_opus")
os.makedirs(OUT_DIR, exist_ok=True)


async def generate(session, idx, category, prompt, sem):
    fname = os.path.join(OUT_DIR, f"{idx:02d}_{category}.json")
    if os.path.exists(fname):
        try:
            with open(fname) as f:
                d = json.load(f)
            if d.get("parts"):
                print(f"  SKIP #{idx:02d} - {prompt[:50]}")
                return "skip"
        except:
            pass

    async with sem:
        payload = {
            "prompt": prompt,
            "player_id": f"demo_opus_{idx}",
            "category": category,
            "style": "freestyle",
            "model": MODEL,
        }
        for attempt in range(3):
            try:
                print(f"  ... #{idx:02d} attempt {attempt+1} - {prompt[:50]}")
                async with session.post(
                    f"{API_URL}/api/generate",
                    json=payload,
                    headers={"X-Api-Key": API_KEY},
                    timeout=aiohttp.ClientTimeout(total=180),  # Opus is slower
                ) as resp:
                    data = await resp.json()
                    if data.get("success") and data.get("model"):
                        model_data = data["model"]
                        name = model_data.get("name", prompt[:20])
                        name = name.replace("Origami ", "").replace("origami ", "")
                        model_data["name"] = name
                        with open(fname, "w") as f:
                            json.dump(model_data, f, indent=2)
                        parts = len(model_data.get("parts", []))
                        print(f"  OK  #{idx:02d} ({parts:2d} parts) - {name}")
                        return "ok"
                    else:
                        err = data.get("error", "unknown")
                        print(f"  ERR #{idx:02d} attempt {attempt+1}: {err}")
                        if attempt < 2:
                            await asyncio.sleep(10 * (attempt + 1))
            except Exception as e:
                print(f"  EXC #{idx:02d} attempt {attempt+1}: {e}")
                if attempt < 2:
                    await asyncio.sleep(10 * (attempt + 1))
        return "fail"


async def main():
    total = len(PROMPTS)
    print(f"Generating {total} demo models with {MODEL}...")
    print()
    start = time.time()

    sem = asyncio.Semaphore(2)  # Max 2 concurrent Opus calls
    async with aiohttp.ClientSession() as session:
        tasks = []
        for idx, (category, prompt) in enumerate(PROMPTS):
            tasks.append(generate(session, idx, category, prompt, sem))

        results = await asyncio.gather(*tasks)

    ok = sum(1 for r in results if r == "ok")
    skip = sum(1 for r in results if r == "skip")
    fail = sum(1 for r in results if r == "fail")
    elapsed = time.time() - start

    print()
    print(f"Done in {elapsed:.0f}s: {ok} new, {skip} cached, {fail} failed out of {total}")


if __name__ == "__main__":
    asyncio.run(main())
