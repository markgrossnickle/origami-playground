"""
Convert competition JSON results into a Luau ModuleScript.

Usage:
    python tools/convert_competition.py

Reads from tools/competition_data/{style}/*.json for each style subfolder.
Outputs src/ReplicatedStorage/Shared/CompetitionData.luau
"""

import json
import os

DATA_DIR = os.path.join(os.path.dirname(__file__), "competition_data")
OUTPUT = os.path.join(os.path.dirname(__file__), "..", "src", "ReplicatedStorage", "Shared", "CompetitionData.luau")

# Ordered cheapest to most expensive
MODELS = ["flash25_lite", "flash_lite", "flash25", "flash3", "gpt_mini", "gpt54_nano", "gpt54_mini", "gemini25_pro", "gemini_pro", "opus"]
MODEL_DISPLAY = {
    "flash25_lite": "FL 2.5 Lite",
    "flash_lite": "FL 3.1 Lite",
    "flash25": "Gem 2.5 Flash",
    "flash3": "Gem 3 Flash",
    "gpt_mini": "4.1 Mini",
    "gpt54_nano": "5.4 Nano",
    "gpt54_mini": "5.4 Mini",
    "gemini25_pro": "Gem 2.5 Pro",
    "gemini_pro": "Gem 3.1 Pro",
    "opus": "Opus",
}

PROMPTS = [
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


def lua_string(s: str) -> str:
    """Escape a string for Luau."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def to_lua(obj, indent=0) -> str:
    """Convert a Python object to a Luau table literal."""
    pad = "\t" * indent
    pad1 = "\t" * (indent + 1)

    if obj is None:
        return "nil"
    elif isinstance(obj, bool):
        return "true" if obj else "false"
    elif isinstance(obj, (int, float)):
        return str(obj)
    elif isinstance(obj, str):
        return lua_string(obj)
    elif isinstance(obj, list):
        if not obj:
            return "{}"
        # Check if it's a simple array of numbers (like position/size/color)
        if all(isinstance(x, (int, float)) for x in obj) and len(obj) <= 4:
            return "{ " + ", ".join(str(x) for x in obj) + " }"
        items = []
        for item in obj:
            items.append(f"{pad1}{to_lua(item, indent + 1)},")
        return "{\n" + "\n".join(items) + f"\n{pad}" + "}"
    elif isinstance(obj, dict):
        if not obj:
            return "{}"
        items = []
        for k, v in obj.items():
            # Use ["key"] syntax for keys with special chars, otherwise key =
            if k.isidentifier() and not k.startswith("_"):
                items.append(f"{pad1}{k} = {to_lua(v, indent + 1)},")
            else:
                items.append(f'{pad1}[{lua_string(k)}] = {to_lua(v, indent + 1)},')
        return "{\n" + "\n".join(items) + f"\n{pad}" + "}"
    else:
        return str(obj)


def collect_style_results(style_dir: str) -> tuple[dict, dict]:
    """Collect results for one style. Returns (results_dict, stats_dict)."""
    results = {}
    stats = {"success": 0, "failed": 0, "missing": 0}

    for i, prompt_info in enumerate(PROMPTS):
        for model in MODELS:
            key = f"{i + 1}_{model}"
            fp = os.path.join(style_dir, f"{prompt_info['category']}_{i:02d}_{model}.json")

            if not os.path.exists(fp):
                stats["missing"] += 1
                continue

            with open(fp) as f:
                data = json.load(f)

            if data.get("_failed"):
                stats["failed"] += 1
                continue

            stats["success"] += 1
            clean = {}
            for field in ("name", "parts", "category", "locomotion", "animation"):
                if field in data:
                    clean[field] = data[field]
            results[key] = clean

    return results, stats


def main():
    # Discover style subdirectories
    styles = []
    for entry in sorted(os.listdir(DATA_DIR)):
        style_dir = os.path.join(DATA_DIR, entry)
        if os.path.isdir(style_dir) and not entry.startswith("."):
            styles.append(entry)

    if not styles:
        print("No style subdirectories found in", DATA_DIR)
        return

    print(f"Found styles: {', '.join(styles)}")

    lines = []
    lines.append("-- Auto-generated by tools/convert_competition.py. Do not edit manually.")
    lines.append("local CompetitionData = {}\n")

    # Models
    lines.append("CompetitionData.MODELS = { " + ", ".join(f'"{m}"' for m in MODELS) + " }\n")

    # Display names
    display_items = ", ".join(f'{k} = "{v}"' for k, v in MODEL_DISPLAY.items())
    lines.append(f"CompetitionData.MODEL_DISPLAY = {{ {display_items} }}\n")

    # Styles
    lines.append("CompetitionData.STYLES = { " + ", ".join(f'"{s}"' for s in styles) + " }\n")

    # Prompts
    lines.append("CompetitionData.PROMPTS = {")
    for p in PROMPTS:
        lines.append(f'\t{{ prompt = {lua_string(p["prompt"])}, category = "{p["category"]}" }},')
    lines.append("}\n")

    # Results per style
    lines.append("CompetitionData.RESULTS = {")
    total_stats = {"success": 0, "failed": 0, "missing": 0}

    for style in styles:
        style_dir = os.path.join(DATA_DIR, style)
        results, stats = collect_style_results(style_dir)

        for k in ("success", "failed", "missing"):
            total_stats[k] += stats[k]

        lines.append(f'\t["{style}"] = {{')
        for i, prompt_info in enumerate(PROMPTS):
            for model in MODELS:
                key = f"{i + 1}_{model}"
                if key in results:
                    lua_val = to_lua(results[key], 2)
                    lines.append(f'\t\t["{key}"] = {lua_val},')
        lines.append("\t},")

        print(f"  {style}: {stats['success']} ok, {stats['failed']} failed, {stats['missing']} missing")

    lines.append("}\n")
    lines.append("return CompetitionData")

    output = "\n".join(lines) + "\n"

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w", newline="\n") as f:
        f.write(output)

    print(f"\nGenerated: {OUTPUT}")
    print(f"  Total success: {total_stats['success']}")
    print(f"  Total failed:  {total_stats['failed']}")
    print(f"  Total missing: {total_stats['missing']}")
    print(f"  File size: {len(output):,} bytes")


if __name__ == "__main__":
    main()
