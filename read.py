#!/usr/bin/env python3
"""
read.py — unified project exporter (override-first).

What it does:
1) Scans a target folder, not the CWD (unless you disable override).
2) Produces one TXT report with:
   - Export Summary (up-front header)
   - Environment fingerprint (shows scanned folder)
   - Directory tree (honouring ignores)
   - File list & stats (brief or full)
   - Concatenated file contents (text-like files only by default)

How to use (simple):
- Edit ROOT_FOLDER (and optionally OUTPUT_FILE) below, then run:  python3 read.py
- If OUTPUT_FILE is empty, the script writes to "<folder_name>_snapshot.txt" inside the scanned folder.

Toggles (edit constants; no CLI flags):
- USE_OVERRIDE:  True -> scan ROOT_FOLDER; False -> scan CWD
- BRIEF_MODE:    Only show Top-N largest in stats (less noise)
- TOP_N_LARGEST: When BRIEF_MODE=True
- SORT_LISTING:  Sort names (prettier, slightly slower)
- HUMAN_TIME:    Human-readable timestamps
- FINGERPRINT_EXT:Probe Node/.NET versions (spawns subprocesses)
- MAX_FILE_BYTES:> this size, skip line counting + content dump
- DUMP_CONTENT:  True -> include concatenated file contents
- DUMP_TEXT_ONLY:Only dump extensions listed in TEXT_EXTS
- IGNORE_DIRS:   Directories to skip entirely
- IGNORE_FILENAMES:Exact filenames to skip everywhere
- IGNORE_FILE_EXT:Extensions to skip everywhere
"""

from __future__ import annotations
import os
import sys
import platform
import subprocess
from datetime import datetime
from pathlib import Path
from typing import List, Set

# ====================== Config (edit here) ======================
# Always specify the folder you want to scan here:
ROOT_FOLDER = "/Users/yx.xu/Desktop/project/ai_council"  # e.g. "/Users/xxx/Desktop/myproj"
# Where to write the output file. Leave empty to auto: "<folder>_snapshot.txt" in the scanned folder.
OUTPUT_FILE = "/Users/yx.xu/Desktop/project/project_context.txt"  # e.g. "/Users/xxx/Desktop/myproj_dump.txt"

# Force using the override path by default (as requested)
USE_OVERRIDE = True

BRIEF_MODE = True
TOP_N_LARGEST = 15
SORT_LISTING = False
HUMAN_TIME = True
FINGERPRINT_EXT = False
MAX_FILE_BYTES = 5 * 1024 * 1024  # 5MB
DUMP_CONTENT = True
DUMP_TEXT_ONLY = True

# Text-like extensions for content dump (add as you need)
TEXT_EXTS = {
    ".txt", ".md", ".py", ".ipynb", ".json", ".yml", ".yaml", ".ini", ".cfg",
    ".toml", ".csv", ".tsv", ".xml", ".html", ".htm", ".css", ".js", ".ts",
    ".tsx", ".jsx", ".c", ".h", ".cpp", ".hpp", ".cs", ".java", ".kt", ".go",
    ".rs", ".rb", ".php", ".sh", ".zsh", ".bash", ".ps1", ".sql", ".r", ".m",
    ".swift", ".pl", ".lua", ".dart", ".scala", ".hs"
}

TEXT_FILENAMES = {
    "Dockerfile", "Makefile", "README", "LICENSE", ".gitignore", ".npmrc",
    ".editorconfig", ".env.example", ".env.local.example"
}

IGNORE_DIRS = {
    ".git", ".idea", ".vscode", "__pycache__", ".pytest_cache", ".mypy_cache",
    "node_modules", "dist", "build", "target", "bin", "obj", ".venv", "venv",
    ".cache", ".tox", ".gradle", ".svelte-kit", ".next", "browser-profiles"
}

IGNORE_FILE_EXT = {
    ".dll", ".so", ".dylib", ".a", ".lib", ".exe",
    ".zip", ".tar", ".gz", ".7z",
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico",
    ".pdf", ".mp4", ".mov", ".mp3", ".wav",
    ".tflite", ".db", ".sqlite", ".sqlite3", ".wal", ".journal", ".ldb",
    ".pak", ".dat", ".bin", ".woff", ".woff2", ".ttf", ".otf",
}

IGNORE_FILENAMES = {
    ".DS_Store", "Thumbs.db", "ai_council.md", "project_context.txt"
}
# ================================================================


def _run_version(cmd: List[str]) -> str:
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=False)
        s = (out.stdout or out.stderr or "").strip()
        return s if s else "not available"
    except Exception:
        return "not available"


def env_fingerprint(scanned_root: Path) -> str:
    parts = []
    parts.append("# Environment")
    parts.append(f"- Scanned Dir: {scanned_root}")
    tz = datetime.now().astimezone().tzinfo
    parts.append(f"- Timestamp:   {datetime.now().astimezone().isoformat(timespec='seconds')} {tz}")
    parts.append(f"- OS:          {platform.system()} {platform.release()} ({platform.machine()})")
    parts.append(f"- Python:      {platform.python_version()}")
    if FINGERPRINT_EXT:
        parts.append(f"- Node:        {_run_version(['node', '-v'])}")
        parts.append(f"- .NET:        {_run_version(['dotnet', '--version'])}")
    else:
        parts.append(f"- Node:        (skipped)")
        parts.append(f"- .NET:        (skipped)")
    return "\n".join(parts)


def human_bytes(n: int) -> str:
    step = 1024.0
    units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
    size = float(n)
    for u in units:
        if size < step:
            return f"{size:.1f}{u}"
        size /= step
    return f"{size:.1f}ZB"


def count_lines(path: Path) -> int:
    """Count lines by reading chunks and counting b'\\n' to minimize Python loop overhead."""
    try:
        with path.open("rb") as f:
            buf = f.read(1 << 20)  # 1MB
            total = 0
            saw_any = False
            last_byte = b""
            while buf:
                saw_any = True
                total += buf.count(b"\\n")
                last_byte = buf[-1:]
                buf = f.read(1 << 20)
            if saw_any and last_byte != b"\n":
                total += 1
            return total
    except Exception:
        return -1  # unknown / unreadable


def decode_text_bytes(raw: bytes) -> str | None:
    if not raw:
        return ""

    if b"\x00" in raw:
        for encoding in ("utf-16", "utf-16-le", "utf-16-be"):
            try:
                return raw.decode(encoding)
            except UnicodeDecodeError:
                continue
        return None

    for encoding in ("utf-8", "utf-8-sig"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue

    return None


def is_probably_text(path: Path) -> bool:
    try:
        with path.open("rb") as f:
            sample = f.read(8192)
    except Exception:
        return False

    return decode_text_bytes(sample) is not None


def listdir_sorted(p: Path):
    try:
        items = list(p.iterdir())
    except Exception:
        return []
    if SORT_LISTING:
        items.sort(key=lambda x: (not x.is_dir(), x.name.lower()))
    return items


def should_ignore_file(p: Path, excluded_paths: Set[Path] | None = None) -> bool:
    if excluded_paths and p in excluded_paths:
        return True
    if p.name in IGNORE_FILENAMES:
        return True
    if p.suffix.lower() in IGNORE_FILE_EXT:
        return True
    return False


def build_tree_lines(root: Path, excluded_paths: Set[Path] | None = None):
    """ASCII tree for directories/files (honours ignores)."""
    lines = []
    root_name = root.name or str(root)
    lines.append(f"{root_name}/")

    def walk(p: Path, prefix: str = "") -> None:
        items = listdir_sorted(p)
        visible = []
        for item in items:
            if item.is_dir() and item.name in IGNORE_DIRS:
                continue
            if item.is_file() and should_ignore_file(item, excluded_paths):
                continue
            if excluded_paths and item in excluded_paths:
                continue
            visible.append(item)

        length = len(visible)
        for idx, item in enumerate(visible):
            is_last = idx == length - 1
            branch = "└── " if is_last else "├── "
            if item.is_dir():
                lines.append(f"{prefix}{branch}{item.name}/")
                walk(item, prefix + ("    " if is_last else "│   "))
            else:
                lines.append(f"{prefix}{branch}{item.name}")
    walk(root)
    return lines


def file_iter(root: Path, excluded_paths: Set[Path] | None = None):
    """Yield file paths under root, honouring ignore lists."""
    for current, dirs, files in os.walk(root):
        dirs[:] = [
            d for d in dirs
            if d not in IGNORE_DIRS
            and not (excluded_paths and ((Path(current) / d) in excluded_paths))
        ]
        if SORT_LISTING:
            dirs.sort(key=lambda s: s.lower())
            files.sort(key=lambda s: s.lower())
        for f in files:
            p = Path(current) / f
            if should_ignore_file(p, excluded_paths):
                continue
            yield p


def file_stats_table(root: Path, excluded_paths: Set[Path] | None = None):
    """Return (rows, file_count, total_bytes, total_lines, collected)."""
    header = f"{'Path':<60}  {'Size':>10}  {'Lines':>7}  {'Modified (local)':>20}"
    sep = "-" * len(header)
    rows = [header, sep]

    file_count = 0
    total_bytes = 0
    total_lines = 0
    collected = []  # (rel_path, size)

    for p in file_iter(root, excluded_paths):
        try:
            stat = p.stat()
        except Exception:
            continue

        size = stat.st_size
        rel = str(p.relative_to(root))
        collected.append((rel, size))

        if HUMAN_TIME:
            mtime = datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
        else:
            mtime = str(int(stat.st_mtime))

        if size > MAX_FILE_BYTES:
            nlines = -1
        else:
            nlines = count_lines(p)

        if nlines >= 0:
            total_lines += nlines
        total_bytes += size
        file_count += 1

        if not BRIEF_MODE:
            rows.append(f"{rel:<60}  {human_bytes(size):>10}  {nlines:>7}  {mtime:>20}")

    if BRIEF_MODE:
        rows = [header, sep]
        rows.append(f"{'** BRIEF MODE: details omitted; see Top-N below **':<60}  {'-':>10}  {'-':>7}  {'-':>20}")
        rows.append("")
        rows.append(f"Top {TOP_N_LARGEST} largest files:")
        for rel, sz in sorted(collected, key=lambda x: x[1], reverse=True)[:TOP_N_LARGEST]:
            rows.append(f"{rel:<60}  {human_bytes(sz):>10}")

    rows.append(sep)
    rows.append(f"{'TOTALS':<60}  {human_bytes(total_bytes):>10}  {total_lines:>7}  {'files:'+str(file_count):>20}")
    return rows, file_count, total_bytes, total_lines, collected


def should_dump(p: Path, size: int) -> bool:
    if size > MAX_FILE_BYTES:
        return False
    if DUMP_TEXT_ONLY:
        return (
            p.suffix.lower() in TEXT_EXTS
            or p.name in TEXT_FILENAMES
            or (p.suffix == "" and is_probably_text(p))
        )
    return True


def dump_contents_section(root: Path, excluded_paths: Set[Path] | None = None):
    """Return concatenated content section with BEGIN/END markers per file."""
    lines = []
    lines.append("# Concatenated File Contents")
    for p in file_iter(root, excluded_paths):
        try:
            stat = p.stat()
        except Exception:
            continue
        if not should_dump(p, stat.st_size):
            continue
        rel = str(p.relative_to(root))
        lines.append("")
        lines.append(f"===== BEGIN FILE: {rel} =====")
        try:
            with p.open("rb") as f:
                raw = f.read()
            txt = decode_text_bytes(raw)
            if txt is None:
                lines.append("[SKIPPED] Non-text or unsupported encoding.")
                lines.append(f"===== END FILE: {rel} =====")
                lines.append("")
                continue
            lines.append(txt.rstrip("\n"))
        except Exception as e:
            lines.append(f"[ERROR] Could not read file: {e}")
        lines.append(f"===== END FILE: {rel} =====")
        lines.append("")
    return lines


def main() -> int:
    if USE_OVERRIDE and (
        "/Users/yourname/path/to/project" in ROOT_FOLDER
        or ROOT_FOLDER.strip() == ""
    ):
        print("[ERROR] ROOT_FOLDER looks like a placeholder; set it to a real directory.", file=sys.stderr)
        return 2

    if USE_OVERRIDE:
        root = Path(ROOT_FOLDER).expanduser().resolve()
    else:
        root = Path.cwd()
    if not root.exists() or not root.is_dir():
        print(f"[ERROR] Invalid ROOT_FOLDER directory: {root}", file=sys.stderr)
        return 2

    if OUTPUT_FILE and OUTPUT_FILE.strip():
        out_path = Path(OUTPUT_FILE).expanduser().resolve()
    else:
        out_path = root / f"{root.name}_snapshot.txt"

    excluded_paths: Set[Path] = set()
    try:
        out_path.relative_to(root)
        excluded_paths.add(out_path)
    except ValueError:
        pass

    env = env_fingerprint(root)
    tree = build_tree_lines(root, excluded_paths)
    table_lines, file_count, total_bytes, total_lines, collected = file_stats_table(root, excluded_paths)
    contents = dump_contents_section(root, excluded_paths) if DUMP_CONTENT else []

    header = []
    header.append("✅ Export complete.")
    header.append(f"   Output: {out_path}")
    header.append(f"   Files exported: {file_count}")
    header.append(f"   Lines written : {total_lines}")
    header.append(f"   Bytes (source): {sum(sz for _, sz in collected)}")
    try:
        est = sum(len(s) + 1 for s in (env.splitlines() + tree + table_lines + contents))
        header.append(f"   Bytes (output): ~{est}")
    except Exception:
        pass

    content = []
    content += header
    content.append("")
    content.append(env)
    content.append("")
    content.append("# Directory Tree")
    content += tree
    content.append("")
    content.append("# File List & Stats")
    content += table_lines
    content.append("")
    if DUMP_CONTENT:
        content += contents
    content.append("")
    content.append(f"_Generated by read.py for {root}_")

    try:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(content) + "\n")
        print(f"[OK] Wrote snapshot to: {out_path}")
    except Exception as e:
        print(f"[ERROR] Failed to write {out_path}: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
