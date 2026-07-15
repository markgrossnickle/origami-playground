#!/usr/bin/env python3
"""codemap.py - emit a compact structural map of a repo.

A briefing artifact for AI build-sessions: directory tree, ranked key files with
their key symbols, entry points, and repo stats. Small and skimmable by design.

Usage:
    codemap.py <repo_path> [--json] [--top N] [--out FILE]
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

SKIP_DIRS = {
    "node_modules", ".git", "dist", "build", ".next", "coverage", "vendor",
    "__pycache__", ".venv", "venv", ".tox", ".mypy_cache", ".pytest_cache",
    "out", "target", ".idea", ".vscode", "Pods", ".gradle", "bower_components",
    ".cache", "tmp", ".turbo", "site-packages", ".svelte-kit",
    ".worktrees", ".worktree",
}

LANG_BY_EXT = {
    ".ts": "TypeScript", ".tsx": "TypeScript", ".mts": "TypeScript", ".cts": "TypeScript",
    ".js": "JavaScript", ".jsx": "JavaScript", ".mjs": "JavaScript", ".cjs": "JavaScript",
    ".py": "Python", ".pyi": "Python",
    ".luau": "Luau", ".lua": "Lua",
    ".go": "Go", ".rs": "Rust", ".rb": "Ruby", ".java": "Java", ".kt": "Kotlin",
    ".swift": "Swift", ".c": "C", ".h": "C", ".cpp": "C++", ".cc": "C++", ".hpp": "C++",
    ".cs": "C#", ".php": "PHP", ".sh": "Shell", ".bash": "Shell", ".zsh": "Shell",
    ".css": "CSS", ".scss": "CSS", ".sass": "CSS", ".less": "CSS",
    ".html": "HTML", ".vue": "Vue", ".svelte": "Svelte",
    ".json": "JSON", ".yml": "YAML", ".yaml": "YAML", ".toml": "TOML",
    ".md": "Markdown", ".sql": "SQL", ".graphql": "GraphQL", ".gql": "GraphQL",
}

LUA_EXTS = {".lua", ".luau"}

# Extensions we bother extracting symbols / imports from.
CODE_EXTS = {
    ".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs",
    ".py", ".pyi", ".vue", ".svelte", ".lua", ".luau",
}

# Files we never treat as "key files" even if large.
NOISE_NAMES = {
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "poetry.lock",
    "Cargo.lock", "composer.lock", "Gemfile.lock",
}

# Output of this tool. Excluded from enumeration entirely: a generated artifact
# should never describe itself, and counting it would make the map's own stats
# depend on whether it happened to be committed yet -- which flips the output
# between the first run and every run after, breaking CI staleness checks.
GENERATED_NAMES = {"CODEMAP.md"}

BINARY_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".svg", ".pdf", ".zip",
    ".gz", ".tar", ".mp3", ".mp4", ".mov", ".wav", ".ogg", ".woff", ".woff2",
    ".ttf", ".otf", ".eot", ".glb", ".gltf", ".fbx", ".obj", ".bin", ".wasm",
    ".psd", ".ai", ".sketch", ".exr", ".hdr", ".dds", ".ktx2", ".basis",
}

ENTRY_STEMS = {"index", "main", "app", "server"}

ROBLOX_SCRIPT = re.compile(r"\.(server|client)\.luau?$", re.I)

# Paths that are real code but rarely what you brief on: frozen version
# snapshots, archived copies, generated output, test fixtures. These get a
# rank penalty so live source wins the top slots.
DEMOTE_PATTERNS = [
    (re.compile(r"(^|/)versions?/v?\d+[._]\d+", re.I), 0.15),
    (re.compile(r"(^|/)(legacy|archive|archived|deprecated|old|backup)(/|$)", re.I), 0.15),
    (re.compile(r"(^|/)__snapshots__(/|$)"), 0.1),
    (re.compile(r"(^|/)(generated|__generated__|gen)(/|$)", re.I), 0.25),
    (re.compile(r"(^|/)_?tmp(/|$)", re.I), 0.15),
    (re.compile(r"(^|/)(fixtures?|mocks?|__mocks__|testdata)(/|$)", re.I), 0.3),
    (re.compile(r"(^|/)(tests?|__tests__|spec|e2e)(/|$)", re.I), 0.5),
    (re.compile(r"\.(test|spec)\.[jt]sx?$", re.I), 0.5),
    (re.compile(r"\.min\.js$", re.I), 0.05),
    (re.compile(r"\.d\.ts$", re.I), 0.4),
    (re.compile(r"(^|/)(examples?|demos?|samples?|playground)(/|$)", re.I), 0.4),
]


def demotion(rel):
    """Multiplier <= 1.0 applied to a file's rank score."""
    posix = rel.replace(os.sep, "/")
    factor = 1.0
    for pat, mult in DEMOTE_PATTERNS:
        if pat.search(posix):
            factor = min(factor, mult)
    return factor

MAX_SYMBOLS = 12
MAX_FILE_BYTES = 2 * 1024 * 1024  # don't read anything bigger than this


# --------------------------------------------------------------------------
# file enumeration
# --------------------------------------------------------------------------

def is_git_repo(path):
    return subprocess.call(
        ["git", "-C", path, "rev-parse", "--is-inside-work-tree"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ) == 0


def repo_name_for(path):
    """Prefer the git remote's repo name over the local directory name.

    The map is committed and re-verified by CI, which checks out into a
    directory named after the *remote* repo -- that name is often not what the
    working copy happens to be called locally, and a worktree is never called
    it. Deriving from the remote keeps the output identical everywhere.
    """
    try:
        url = subprocess.check_output(
            ["git", "-C", path, "remote", "get-url", "origin"],
            stderr=subprocess.DEVNULL,
        ).decode().strip()
    except (subprocess.CalledProcessError, OSError):
        return os.path.basename(path)
    name = url.rstrip("/").rsplit("/", 1)[-1]
    if name.endswith(".git"):
        name = name[:-4]
    return name or os.path.basename(path)


def list_files_git(path):
    out = subprocess.check_output(
        ["git", "-C", path, "ls-files", "-z"], stderr=subprocess.DEVNULL
    )
    files = [f for f in out.decode("utf-8", "replace").split("\0") if f]
    # git ls-files ignores .gitignore but not our vendored-dir preferences
    return [f for f in files if not _in_skip_dir(f)]


def _in_skip_dir(rel):
    return any(part in SKIP_DIRS for part in rel.split(os.sep))


def list_files_walk(path):
    found = []
    for root, dirs, names in os.walk(path):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for n in names:
            if n.startswith("."):
                continue
            rel = os.path.relpath(os.path.join(root, n), path)
            if not _in_skip_dir(rel):
                found.append(rel)
    return found


def enumerate_files(path):
    if is_git_repo(path):
        try:
            files, source = list_files_git(path), "git ls-files"
        except subprocess.CalledProcessError:
            files, source = list_files_walk(path), "filesystem walk"
    else:
        files, source = list_files_walk(path), "filesystem walk"
    return [f for f in files if os.path.basename(f) not in GENERATED_NAMES], source


# --------------------------------------------------------------------------
# symbol extraction
# --------------------------------------------------------------------------

TS_PATTERNS = [
    # export function foo / export async function foo
    (re.compile(r"^\s*export\s+(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)", re.M), "fn"),
    (re.compile(r"^\s*export\s+(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)", re.M), "class"),
    (re.compile(r"^\s*export\s+interface\s+([A-Za-z_$][\w$]*)", re.M), "interface"),
    (re.compile(r"^\s*export\s+type\s+([A-Za-z_$][\w$]*)", re.M), "type"),
    (re.compile(r"^\s*export\s+(?:const\s+)?enum\s+([A-Za-z_$][\w$]*)", re.M), "enum"),
    (re.compile(r"^\s*export\s+(?:const|let|var)\s+([A-Za-z_$][\w$]*)", re.M), "const"),
]

TS_DEFAULT_NAMED = re.compile(
    r"^\s*export\s+default\s+(?:async\s+)?(?:function\s*\*?\s*|class\s+)([A-Za-z_$][\w$]*)", re.M
)
TS_DEFAULT_ANY = re.compile(r"^\s*export\s+default\s+", re.M)
TS_EXPORT_LIST = re.compile(r"^\s*export\s*\{([^}]*)\}", re.M)

# CommonJS: module.exports = / exports.foo =
CJS_NAMED = re.compile(r"^\s*(?:module\.)?exports\.([A-Za-z_$][\w$]*)\s*=", re.M)

PY_DEF = re.compile(r"^(?:async\s+)?def\s+([A-Za-z_]\w*)", re.M)
PY_CLASS = re.compile(r"^class\s+([A-Za-z_]\w*)", re.M)

# --- Luau / Lua -----------------------------------------------------------
# Roblox modules are tables returned at end-of-file; the returned name is the
# module identity, and `function M:foo()` / `function M.foo()` hanging off it
# are its API. Plain `function foo()` globals are vanishingly rare in Roblox
# code, so the method forms carry nearly all the signal.
LUA_RETURN = re.compile(r"^return\s+([A-Za-z_]\w*)\s*$", re.M)
LUA_KNIT = re.compile(
    r"^local\s+([A-Za-z_]\w*)\s*=\s*Knit\.Create(Controller|Service)", re.M)
LUA_METHOD = re.compile(r"^function\s+([A-Za-z_]\w*)\s*([.:])\s*(\w+)\s*\(", re.M)
LUA_FUNC = re.compile(r"^function\s+([A-Za-z_]\w*)\s*\(", re.M)
LUA_LOCAL_FUNC = re.compile(r"^local\s+function\s+([A-Za-z_]\w*)", re.M)
LUA_TYPE = re.compile(r"^(?:export\s+)?type\s+([A-Za-z_]\w*)", re.M)
LUA_FIELD_FUNC = re.compile(r"^([A-Za-z_]\w*)\s*[.:]\s*(\w+)\s*=\s*function", re.M)
LUA_TABLE = re.compile(r"^local\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=\s*\{", re.M)
# require(ReplicatedStorage.Shared.Config) / require(script.Parent.Foo) /
# require(RS:WaitForChild("Client"):WaitForChild("Main")) -- one nesting level.
LUA_REQUIRE = re.compile(r"require\s*\(([^()]*(?:\([^()]*\)[^()]*)*)\)")
LUA_WAITFORCHILD = re.compile(r"""WaitForChild\s*\(\s*["']([^"']+)["']""")
LUA_DOTTED = re.compile(r"\.\s*([A-Za-z_]\w*)")
LUA_QUOTED = re.compile(r"""^\s*["']([^"']+)["']\s*$""")
LUA_PLAIN = re.compile(r"^\s*([A-Za-z_]\w*)\s*$")

IMPORT_FROM = re.compile(r"""(?:^|\s)(?:import|export)[^;\n]*?from\s+['"]([^'"]+)['"]""", re.M)
IMPORT_BARE = re.compile(r"""^\s*import\s+['"]([^'"]+)['"]""", re.M)
REQUIRE = re.compile(r"""require\s*\(\s*['"]([^'"]+)['"]\s*\)""")
DYN_IMPORT = re.compile(r"""(?<!\w)import\s*\(\s*['"]([^'"]+)['"]\s*\)""")

PY_IMPORT = re.compile(r"^\s*(?:from\s+([.\w]+)\s+import|import\s+([.\w]+))", re.M)

REACT_COMPONENT = re.compile(r"^[A-Z][A-Za-z0-9]*$")


def strip_comments(src):
    """Crude block/line comment removal so patterns don't match commented code."""
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"^\s*//.*$", "", src, flags=re.M)
    return src


def strip_lua_comments(src):
    """Same idea for Lua: long-bracket comments --[[ ]] / --[=[ ]=] then --."""
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", "", src, flags=re.S)
    src = re.sub(r"--.*$", "", src, flags=re.M)
    return src


def luau_require_name(expr):
    """Reduce a require(...) expression to the required module's name."""
    wfc = LUA_WAITFORCHILD.findall(expr)
    if wfc:
        return wfc[-1]
    dotted = LUA_DOTTED.findall(expr)
    if dotted:
        return dotted[-1]
    m = LUA_QUOTED.match(expr)
    if m:
        return m.group(1).rstrip("/").split("/")[-1]
    m = LUA_PLAIN.match(expr)
    return m.group(1) if m else None


def extract_lua_symbols(src):
    """Return (symbols, is_knit) for a Lua/Luau module."""
    syms = []
    seen = set()

    def add(kind, name):
        if name and name not in seen:
            seen.add(name)
            syms.append((kind, name))

    knit_m = LUA_KNIT.search(src)
    returned = LUA_RETURN.findall(src)
    # The returned table is the module's public identity; fall back to a Knit
    # controller/service, then to any top-level table declaration.
    module = None
    if returned:
        module = returned[-1]
    elif knit_m:
        module = knit_m.group(1)
    if module is None:
        t = LUA_TABLE.search(src)
        if t:
            module = t.group(1)
    if module:
        add("module", module)

    # Methods on the module first, then methods on anything else.
    methods = [(recv, sep, name) for recv, sep, name in LUA_METHOD.findall(src)]
    methods += [(recv, ".", name) for recv, name in LUA_FIELD_FUNC.findall(src)]
    own = [m for m in methods if module and m[0] == module]
    other = [m for m in methods if not (module and m[0] == module)]

    def public_first(ms):
        return ([m for m in ms if not m[2].startswith("_")] +
                [m for m in ms if m[2].startswith("_")])

    for recv, sep, name in public_first(own):
        add("method", name)
    for recv, sep, name in public_first(other):
        add("method", recv + sep + name)

    for name in LUA_FUNC.findall(src):
        add("fn", name)
    for name in LUA_TYPE.findall(src):
        add("type", name)
    for name in LUA_LOCAL_FUNC.findall(src):
        add("local", name)

    return syms, bool(knit_m)


def looks_like_component(name, src, ext):
    if ext not in (".tsx", ".jsx"):
        return False
    return bool(REACT_COMPONENT.match(name)) and ("</" in src or "jsx" in src.lower())


def extract_symbols(rel, src, ext):
    """Return (symbols, is_react, is_knit); symbols is a list of (kind, name)."""
    syms = []
    seen = set()

    def add(kind, name):
        if name and name not in seen:
            seen.add(name)
            syms.append((kind, name))

    if ext in (".py", ".pyi"):
        for m in PY_CLASS.finditer(src):
            add("class", m.group(1))
        for m in PY_DEF.finditer(src):
            add("fn", m.group(1))
        return syms, False, False

    if ext in LUA_EXTS:
        lua_syms, knit = extract_lua_symbols(strip_lua_comments(src))
        return lua_syms, False, knit

    body = strip_comments(src)
    react = False

    m = TS_DEFAULT_NAMED.search(body)
    if m:
        add("default", m.group(1))
    elif TS_DEFAULT_ANY.search(body):
        add("default", "default")

    for pattern, kind in TS_PATTERNS:
        for mm in pattern.finditer(body):
            name = mm.group(1)
            k = kind
            if kind in ("fn", "const") and looks_like_component(name, body, ext):
                k = "component"
                react = True
            add(k, name)

    for mm in TS_EXPORT_LIST.finditer(body):
        for piece in mm.group(1).split(","):
            piece = piece.strip()
            if not piece or piece.startswith("*"):
                continue
            # handle `foo as bar`
            name = piece.split(" as ")[-1].strip()
            name = re.sub(r"^type\s+", "", name).strip()
            if re.match(r"^[A-Za-z_$][\w$]*$", name):
                add("re-export", name)

    for mm in CJS_NAMED.finditer(body):
        add("export", mm.group(1))

    if not react and ext in (".tsx", ".jsx"):
        react = "</" in body or "React" in body

    return syms, react, False


def extract_imports(src, ext):
    if ext in (".py", ".pyi"):
        out = []
        for m in PY_IMPORT.finditer(src):
            out.append(m.group(1) or m.group(2))
        return out
    if ext in LUA_EXTS:
        out = []
        for expr in LUA_REQUIRE.findall(strip_lua_comments(src)):
            name = luau_require_name(expr)
            if name:
                out.append(name)
        return out
    body = strip_comments(src)
    out = []
    for pat in (IMPORT_FROM, IMPORT_BARE, REQUIRE, DYN_IMPORT):
        out.extend(pat.findall(body))
    return out


# --------------------------------------------------------------------------
# import resolution (for centrality)
# --------------------------------------------------------------------------

RESOLVE_EXTS = [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".vue", ".svelte", ".py"]


def resolve_import(spec, from_rel, known):
    """Resolve a relative JS/TS import spec to a repo-relative path in `known`."""
    if not spec.startswith("."):
        return None
    base = os.path.normpath(os.path.join(os.path.dirname(from_rel), spec))
    if base in known:
        return base
    for ext in RESOLVE_EXTS:
        cand = base + ext
        if cand in known:
            return cand
    for ext in RESOLVE_EXTS:
        cand = os.path.join(base, "index" + ext)
        if cand in known:
            return cand
    return None


def build_lua_index(files):
    """Map module name -> [paths]. Rojo folds Foo/init.luau into module `Foo`."""
    idx = defaultdict(list)
    for rel, info in files.items():
        if info["ext"] not in LUA_EXTS:
            continue
        stem = os.path.basename(rel)
        for suffix in (".server", ".client"):
            stem = stem.replace(suffix + os.path.splitext(rel)[1], "")
        stem = os.path.splitext(stem)[0]
        if stem == "init":
            parent = os.path.dirname(rel)
            if not parent:
                continue
            stem = os.path.basename(parent)
        idx[stem].append(rel)
    return idx


def resolve_lua_import(name, lua_index):
    """Roblox requires are instance paths, not file paths -- resolve by unique
    module name. Ambiguous names are dropped rather than guessed."""
    hits = lua_index.get(name)
    return hits[0] if hits and len(hits) == 1 else None


def resolve_py_import(spec, from_rel, known):
    if not spec:
        return None
    if spec.startswith("."):
        depth = len(spec) - len(spec.lstrip("."))
        tail = spec.lstrip(".").replace(".", os.sep)
        base = os.path.dirname(from_rel)
        for _ in range(depth - 1):
            base = os.path.dirname(base)
        cand = os.path.normpath(os.path.join(base, tail)) if tail else base
    else:
        cand = spec.replace(".", os.sep)
    for suffix in (".py", os.sep + "__init__.py"):
        if cand + suffix in known:
            return cand + suffix
    return None


# --------------------------------------------------------------------------
# scanning
# --------------------------------------------------------------------------

def count_lines(abspath):
    try:
        with open(abspath, "rb") as fh:
            data = fh.read()
    except OSError:
        return 0, None
    if b"\0" in data[:4096]:
        return 0, None
    text = data.decode("utf-8", "replace")
    n = text.count("\n") + (1 if text and not text.endswith("\n") else 0)
    return n, text


def scan(repo, rels):
    files = {}
    for rel in rels:
        ab = os.path.join(repo, rel)
        ext = os.path.splitext(rel)[1].lower()
        try:
            size = os.path.getsize(ab)
        except OSError:
            continue
        info = {
            "path": rel,
            "ext": ext,
            "lang": LANG_BY_EXT.get(ext, "other"),
            "bytes": size,
            "lines": 0,
            "symbols": [],
            "imports": [],
            "react": False,
            "knit": False,
            "binary": ext in BINARY_EXTS,
        }
        if info["binary"] or size > MAX_FILE_BYTES or os.path.basename(rel) in NOISE_NAMES:
            files[rel] = info
            continue
        lines, text = count_lines(ab)
        info["lines"] = lines
        if text is None:
            info["binary"] = True
            files[rel] = info
            continue
        if ext in CODE_EXTS:
            syms, react, knit = extract_symbols(rel, text, ext)
            info["symbols"] = syms
            info["react"] = react
            info["knit"] = knit
            info["imports"] = extract_imports(text, ext)
        files[rel] = info
    return files


def read_package_json(repo, rels):
    """Collect declared entry points from any package.json in the repo."""
    entries = []
    for rel in rels:
        if os.path.basename(rel) != "package.json":
            continue
        try:
            with open(os.path.join(repo, rel)) as fh:
                pkg = json.load(fh)
        except (OSError, ValueError):
            continue
        base = os.path.dirname(rel)
        def norm(p):
            return os.path.normpath(os.path.join(base, p)) if base else os.path.normpath(p)
        for key in ("main", "module", "browser", "types"):
            val = pkg.get(key)
            if isinstance(val, str):
                entries.append((norm(val), "package.json:" + key))
        bins = pkg.get("bin")
        if isinstance(bins, str):
            entries.append((norm(bins), "package.json:bin"))
        elif isinstance(bins, dict):
            for _, v in bins.items():
                if isinstance(v, str):
                    entries.append((norm(v), "package.json:bin"))
    return entries


def find_entry_points(files, pkg_entries):
    """Return {rel: [reasons]} for likely entry points."""
    entries = defaultdict(list)
    known = set(files)

    for target, reason in pkg_entries:
        hit = target if target in known else None
        if hit is None:
            for ext in RESOLVE_EXTS:
                if target + ext in known:
                    hit = target + ext
                    break
        if hit:
            entries[hit].append(reason)

    for rel, info in files.items():
        if info["binary"] or info["ext"] not in CODE_EXTS:
            continue
        base = os.path.basename(rel)
        stem = os.path.splitext(base)[0].lower()
        depth = rel.count(os.sep)
        if info["ext"] in LUA_EXTS:
            # Rojo: *.server.luau / *.client.luau are the scripts Roblox
            # actually runs; everything else is a required module.
            m = ROBLOX_SCRIPT.search(base)
            if m:
                entries[rel].append("roblox %s script" % m.group(1).lower())
            elif stem == "main":
                entries[rel].append("entry filename")
            continue
        if stem in ENTRY_STEMS and depth <= 2:
            entries[rel].append("entry filename")
        if stem == "__main__":
            entries[rel].append("python __main__")
    return entries


def compute_centrality(files):
    """How many other files import each file."""
    known = set(files)
    lua_index = build_lua_index(files)
    importers = Counter()
    for rel, info in files.items():
        if not info["imports"]:
            continue
        ext = info["ext"]
        for spec in info["imports"]:
            if ext in (".py", ".pyi"):
                target = resolve_py_import(spec, rel, known)
            elif ext in LUA_EXTS:
                target = resolve_lua_import(spec, lua_index)
            else:
                target = resolve_import(spec, rel, known)
            if target and target != rel:
                importers[target] += 1
    return importers


def rank(files, importers, entries):
    """Score each file: size + centrality, entry points boosted."""
    scored = []
    for rel, info in files.items():
        if info["binary"]:
            continue
        if os.path.basename(rel) in NOISE_NAMES:
            continue
        lines = info["lines"]
        size_score = min(lines, 1500) / 1500.0 * 40.0
        cent = importers.get(rel, 0)
        cent_score = min(cent, 20) / 20.0 * 35.0
        export_score = min(len(info["symbols"]), 15) / 15.0 * 15.0
        entry_score = 25.0 if rel in entries else 0.0
        if info["ext"] not in CODE_EXTS:
            size_score *= 0.35
            export_score = 0.0
        score = (size_score + cent_score + export_score + entry_score) * demotion(rel)
        scored.append((score, rel))
    scored.sort(key=lambda t: (-t[0], t[1]))
    return scored


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------

def summarize_symbols(info, limit=MAX_SYMBOLS):
    syms = info["symbols"]
    if not syms:
        return ""
    shown = syms[:limit]
    parts = []
    for kind, name in shown:
        if kind == "default":
            parts.append("default:" + name if name != "default" else "default export")
        elif kind == "class":
            parts.append(name + "()")
        elif kind == "component":
            parts.append("<" + name + ">")
        elif kind == "method":
            # Own-module methods render as `:foo()`; methods on another
            # receiver already carry their `Recv.foo` / `Recv:foo` prefix.
            qualified = "." in name or ":" in name
            parts.append((name if qualified else ":" + name) + "()")
        elif kind == "type":
            parts.append("type " + name)
        elif kind == "local":
            parts.append("local " + name + "()")
        else:
            parts.append(name)
    text = ", ".join(parts)
    extra = len(syms) - len(shown)
    if extra > 0:
        text += ", +%d more" % extra
    return text


def build_tree(files, max_entries=32):
    """Compact directory tree: code-bearing dirs only, biggest first.

    Asset/binary-only directories are collapsed into a single trailing note --
    they carry no structure worth briefing on.
    """
    dirs = defaultdict(lambda: {"files": 0, "lines": 0, "code": 0})
    for rel, info in files.items():
        d = os.path.dirname(rel) or "."
        parts = d.split(os.sep) if d != "." else ["."]
        is_code = info["ext"] in CODE_EXTS
        for i in range(len(parts)):
            key = os.sep.join(parts[: i + 1])
            dirs[key]["files"] += 1
            dirs[key]["lines"] += info["lines"]
            dirs[key]["code"] += 1 if is_code else 0

    candidates = [k for k in dirs if k.count(os.sep) < 3 and dirs[k]["code"] > 0]
    asset_dirs = sum(
        1 for k in dirs
        if k.count(os.sep) < 3 and dirs[k]["code"] == 0 and k != "."
    )
    # pick the biggest subtrees by LOC, then print them in path order so the
    # tree still reads like a tree
    keep = sorted(candidates, key=lambda k: -dirs[k]["lines"])[:max_entries]
    keep = sorted(keep)

    lines = []
    for k in keep:
        depth = 0 if k == "." else k.count(os.sep)
        name = "." if k == "." else os.path.basename(k)
        d = dirs[k]
        lines.append("%s%s/  (%d files, %s LOC)" % (
            "  " * depth, name, d["files"], fmt_num(d["lines"])))
    dropped = len(candidates) - len(keep)
    if dropped > 0:
        lines.append("... +%d more code directories" % dropped)
    if asset_dirs > 0:
        lines.append("... +%d asset-only directories (no code)" % asset_dirs)
    return lines


def fmt_num(n):
    return "{:,}".format(n)


def repo_stats(files):
    langs = Counter()
    loc = Counter()
    total_loc = 0
    for info in files.values():
        if info["binary"]:
            langs["binary/asset"] += 1
            continue
        langs[info["lang"]] += 1
        loc[info["lang"]] += info["lines"]
        total_loc += info["lines"]
    return langs, loc, total_loc


def render_markdown(data):
    out = []
    a = out.append
    a("# CodeMap: %s" % data["repo_name"])
    a("")
    # Deliberately no absolute path here: this file is committed and verified
    # by CI, which checks out to a different directory than any dev machine.
    a("_%d files | %s LOC | source: %s_" % (
        data["stats"]["total_files"],
        fmt_num(data["stats"]["total_loc"]), data["source"]))
    a("")

    a("## Stats")
    a("")
    langs = data["stats"]["languages"]
    top_langs = sorted(langs.items(), key=lambda kv: -kv[1]["files"])[:8]
    a("| Language | Files | LOC |")
    a("|---|---:|---:|")
    for name, v in top_langs:
        a("| %s | %d | %s |" % (name, v["files"], fmt_num(v["loc"])))
    a("")

    if data["entry_points"]:
        a("## Entry points")
        a("")
        for e in data["entry_points"]:
            a("- `%s` — %s" % (e["path"], ", ".join(e["reasons"])))
        a("")

    a("## Tree")
    a("")
    a("```")
    for line in data["tree"]:
        a(line)
    a("```")
    a("")

    a("## Key files (%d of %d, ranked)" % (len(data["key_files"]), data["stats"]["total_files"]))
    a("")
    for f in data["key_files"]:
        flags = []
        if f["entry"]:
            flags.append("ENTRY")
        if f["imported_by"]:
            flags.append("<-%d" % f["imported_by"])
        if f["react"]:
            flags.append("react")
        if f["knit"]:
            flags.append("knit")
        tag = (" **[%s]**" % " ".join(flags)) if flags else ""
        a("- `%s` (%d L)%s" % (f["path"], f["lines"], tag))
        if f["symbols"]:
            a("  - %s" % f["symbols"])
    a("")
    return "\n".join(out)


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def build_map(repo, top):
    repo = os.path.abspath(repo)
    rels, source = enumerate_files(repo)
    files = scan(repo, rels)
    pkg_entries = read_package_json(repo, rels)
    entries = find_entry_points(files, pkg_entries)
    importers = compute_centrality(files)
    scored = rank(files, importers, entries)

    selected = scored[:top] if top else scored
    key_files = []
    for score, rel in selected:
        info = files[rel]
        key_files.append({
            "path": rel,
            "lines": info["lines"],
            "lang": info["lang"],
            "score": round(score, 1),
            "entry": rel in entries,
            "entry_reasons": entries.get(rel, []),
            "imported_by": importers.get(rel, 0),
            "react": info["react"],
            "knit": info["knit"],
            "symbols": summarize_symbols(info),
            "symbol_list": [{"kind": k, "name": n} for k, n in info["symbols"][:MAX_SYMBOLS]],
            "symbol_count": len(info["symbols"]),
        })

    langs, loc, total_loc = repo_stats(files)
    entry_list = [
        {"path": p, "reasons": sorted(set(r))}
        for p, r in sorted(entries.items(), key=lambda kv: (kv[0].count(os.sep), kv[0]))
        if demotion(p) >= 1.0
    ][:15]

    return {
        "repo_path": repo,
        "repo_name": repo_name_for(repo),
        "source": source,
        "stats": {
            "total_files": len(files),
            "total_loc": total_loc,
            "languages": {
                name: {"files": cnt, "loc": loc.get(name, 0)}
                for name, cnt in langs.items()
            },
        },
        "entry_points": entry_list,
        "tree": build_tree(files),
        "key_files": key_files,
    }


def main():
    ap = argparse.ArgumentParser(description="Emit a compact structural map of a repo.")
    ap.add_argument("repo_path")
    ap.add_argument("--json", action="store_true", help="emit structured JSON")
    ap.add_argument("--top", type=int, default=0, metavar="N",
                    help="cap output to the N most important files")
    ap.add_argument("--out", metavar="FILE", help="write to FILE instead of stdout")
    args = ap.parse_args()

    if not os.path.isdir(args.repo_path):
        sys.stderr.write("error: not a directory: %s\n" % args.repo_path)
        return 2

    data = build_map(args.repo_path, args.top)
    text = json.dumps(data, indent=2) if args.json else render_markdown(data)

    if args.out:
        d = os.path.dirname(os.path.abspath(args.out))
        if d and not os.path.isdir(d):
            os.makedirs(d)
        with open(args.out, "w") as fh:
            fh.write(text + "\n")
        sys.stderr.write("wrote %s (%d lines, %.1f KB)\n" % (
            args.out, text.count("\n") + 1, len(text) / 1024.0))
    else:
        sys.stdout.write(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
