#!/usr/bin/env python3
import argparse
import os
import shutil
import stat
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


@dataclass
class Counts:
    files: int = 0
    dirs: int = 0


def count_tree(root: Path) -> Counts:
    c = Counts()
    for _, dirnames, filenames in os.walk(root):
        c.dirs += len(dirnames)
        c.files += len(filenames)
    return c


def is_target_dir(name: str) -> bool:
    return name in {".terraform", "terraform.tfstate.d"}


def is_target_file(name: str) -> bool:
    # exact names
    if name in {
        "terraform.tfstate",
        "terraform.tfstate.backup",
        ".terraform.lock.hcl",
        "lock.hcl",
    }:
        return True

    # terraform.tfstate.<timestamp>.backup
    if name.startswith("terraform.tfstate.") and name.endswith(".backup"):
        return True

    return False



def collect_targets(root: Path):
    targets = []
    for dirpath, dirnames, filenames in os.walk(root, topdown=True):
        dp = Path(dirpath)

        # prune target dirs so we don't walk into them
        keep_dirs = []
        for d in dirnames:
            if is_target_dir(d):
                targets.append(dp / d)
            else:
                keep_dirs.append(d)
        dirnames[:] = keep_dirs

        for f in filenames:
            if is_target_file(f):
                targets.append(dp / f)

    # unique + delete deeper paths first
    uniq = list({p.resolve(): p for p in targets}.values())
    uniq.sort(key=lambda p: len(str(p)), reverse=True)
    return uniq


def _force_writable(path: str) -> None:
    try:
        os.chmod(path, stat.S_IWRITE)
    except Exception:
        pass


def _rmtree_onerror(func, path, exc_info):
    # Windows: remove readonly + retry
    _force_writable(path)
    try:
        func(path)
    except Exception:
        # re-raise original failure
        raise


def move_to_trash(root: Path, trash_root: Path, p: Path):
    rel = p.relative_to(root)
    dest = trash_root / rel
    dest.parent.mkdir(parents=True, exist_ok=True)

    if dest.exists():
        suffix = datetime.now().strftime("%H%M%S%f")
        dest = dest.with_name(dest.name + f".{suffix}")

    shutil.move(str(p), str(dest))


def delete_path(p: Path):
    if p.is_dir():
        shutil.rmtree(p, onerror=_rmtree_onerror)
        return

    # file
    try:
        p.chmod(stat.S_IWRITE)
    except Exception:
        pass
    p.unlink(missing_ok=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".", help="default: current folder")
    ap.add_argument("--apply", action="store_true", help="actually do it (default is dry-run)")
    ap.add_argument("--trash", action="store_true", help="move targets into .tftrash/<timestamp>/ instead of deleting")
    ap.add_argument("--quiet", action="store_true", help="less output")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    if not root.exists() or not root.is_dir():
        raise SystemExit(f"root not found: {root}")

    before = count_tree(root)
    targets = collect_targets(root)

    del_files = 0
    del_dirs = 0
    failures = []

    trash_root = None
    if args.trash:
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        trash_root = root / ".tftrash" / ts
        trash_root.mkdir(parents=True, exist_ok=True)

    if not args.quiet:
        mode = "APPLY" if args.apply else "DRY-RUN"
        extra = f" + TRASH({trash_root})" if (args.apply and args.trash) else (" + TRASH(prep)" if args.trash else "")
        print(f"root: {root}")
        print(f"mode: {mode}{extra}")
        print("targets:")
        for p in targets:
            print(f"  - {p.relative_to(root)}")

    if args.apply:
        for p in targets:
            if not p.exists():
                continue

            try:
                if p.is_dir():
                    del_dirs += 1
                else:
                    del_files += 1

                if args.trash:
                    move_to_trash(root, trash_root, p)
                else:
                    delete_path(p)

            except Exception as e:
                failures.append((p, repr(e)))

    after = count_tree(root)

    print("\nsummary:")
    print(f"  total before: dirs={before.dirs}, files={before.files}")
    if args.apply:
        print(f"  deleted     : dirs={del_dirs}, files={del_files}")
    else:
        print("  deleted     : dirs=0, files=0 (dry-run)")
    print(f"  remaining   : dirs={after.dirs}, files={after.files}")

    if args.apply and args.trash:
        print(f"  trash path  : {trash_root}")

    if failures:
        print("\nfailed:")
        for p, e in failures:
            print(f"  - {p.relative_to(root)} -> {e}")
        print("\nfix:")
        print("  - close VS Code (especially any window opened on this folder)")
        print("  - stop any terminal that cd'd into these folders")
        print("  - if Defender/AV is scanning, pause it briefly")
        print("  - rerun: py tf_clean.py --apply --trash")


if __name__ == "__main__":
    main()
