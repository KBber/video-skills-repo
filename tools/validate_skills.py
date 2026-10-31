#!/usr/bin/env python3
"""仓库自检：校验 manifest.json 与 skills/、plugins/ 下实际技能目录是否一致。

复刻 MiniMax Code 运行时的 skill 发现规则：
  - 目录内含 SKILL.md → 视为 skill 根，不再递归
  - 否则递归子目录查找 SKILL.md
  - 跳过点目录与 node_modules
  - 仅顶层目录的直接 .md 子文件会被当作 skill

用法：
    python3 tools/validate_skills.py            # 人类可读输出
    python3 tools/validate_skills.py --json     # 机器可读输出
退出码 0 = 全部通过，1 = 有问题。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME_RE = re.compile(r"^[a-z0-9-]+$")
SCAN_ROOTS = ("skills", "plugins")


def parse_frontmatter(path: str) -> dict:
    """读取 SKILL.md 的 YAML frontmatter（只做 key: value 的浅解析）。"""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except OSError:
        return {}
    m = re.match(r"^---[ \t]*\r?\n(.*?)\r?\n---", raw, re.S)
    if not m:
        return {}
    meta = {}
    for line in m.group(1).splitlines():
        km = re.match(r"^([A-Za-z0-9_.-]+):[ \t]*(.*)$", line)
        if not km:
            continue
        val = km.group(2).strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        meta[km.group(1)] = val
    return meta


def discover(root: str, is_top: bool, found: list, errors: list) -> None:
    if not os.path.isdir(root):
        return
    try:
        entries = sorted(os.listdir(root))
    except OSError as exc:
        errors.append(f"无法读取目录 {root}: {exc}")
        return

    if "SKILL.md" in entries:
        skill_file = os.path.join(root, "SKILL.md")
        meta = parse_frontmatter(skill_file)
        desc = (meta.get("description") or "").strip()
        if not desc:
            errors.append(f"{skill_file}: frontmatter 缺少 description")
            return
        name = (meta.get("name") or "").strip() or os.path.basename(root.rstrip("/\\"))
        found.append({"name": name, "path": skill_file, "dir": root})
        return

    for entry in entries:
        if entry.startswith(".") or entry == "node_modules":
            continue
        full = os.path.join(root, entry)
        if os.path.isdir(full):
            discover(full, False, found, errors)
        elif is_top and entry.endswith(".md"):
            meta = parse_frontmatter(full)
            if not (meta.get("description") or "").strip():
                continue
            name = (meta.get("name") or "").strip() or os.path.splitext(entry)[0]
            found.append({"name": name, "path": full, "dir": root})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    ap.add_argument("--repo", default=REPO_ROOT, help="仓库根目录")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    errors: list[str] = []
    warnings: list[str] = []

    manifest_path = os.path.join(repo, "manifest.json")
    if not os.path.isfile(manifest_path):
        print(f"缺少 manifest.json: {manifest_path}", file=sys.stderr)
        return 1
    with open(manifest_path, "r", encoding="utf-8") as fh:
        manifest = json.load(fh)

    # ---- 1. 运行时视角：仓库里实际能发现哪些技能 ----
    discovered: list = []
    for root_name in SCAN_ROOTS:
        discover(os.path.join(repo, root_name), True, discovered, errors)

    names = [d["name"] for d in discovered]
    dup = sorted({n for n in names if names.count(n) > 1})
    for n in dup:
        errors.append(f"技能重名: {n}")
    for d in discovered:
        if not NAME_RE.match(d["name"]):
            errors.append(f"技能名不合法(仅允许小写字母/数字/连字符): {d['name']}  ({d['path']})")

    # ---- 2. manifest 视角：每条记录都要能在仓库里找到 ----
    manifest_entries = []
    for g in manifest.get("groups", []):
        for s in g.get("skills", []):
            manifest_entries.append((g.get("id", "?"), s))

    by_name = {d["name"]: d for d in discovered}
    for gid, s in manifest_entries:
        repo_path = s.get("repoPath", "")
        full = os.path.join(repo, repo_path.replace("/", os.sep))
        if not repo_path:
            errors.append(f"[{gid}] {s.get('name')}: manifest 缺少 repoPath")
            continue
        if not os.path.isdir(full):
            errors.append(f"[{gid}] {s.get('name')}: repoPath 不存在 -> {repo_path}")
            continue
        skill_md = os.path.join(full, "SKILL.md")
        if not os.path.isfile(skill_md):
            errors.append(f"[{gid}] {s.get('name')}: 缺少 SKILL.md -> {repo_path}")
            continue
        meta = parse_frontmatter(skill_md)
        if not (meta.get("description") or "").strip():
            errors.append(f"[{gid}] {s.get('name')}: frontmatter 缺少 description")
        fm_name = (meta.get("name") or "").strip()
        if fm_name != s.get("name"):
            errors.append(
                f"[{gid}] {s.get('name')}: frontmatter name 与 manifest 不一致 ({fm_name or '空'})"
            )
        if s.get("name") not in by_name:
            errors.append(f"[{gid}] {s.get('name')}: 运行时扫描未发现该技能")

    # ---- 3. 反向：仓库里发现的技能都要在 manifest 里登记 ----
    manifest_names = {s.get("name") for _, s in manifest_entries}
    for d in discovered:
        if d["name"] not in manifest_names:
            warnings.append(f"技能未登记在 manifest.json: {d['name']}  ({d['path']})")

    # ---- 4. 扁平技能目录名应与 frontmatter name 一致 ----
    for gid, s in manifest_entries:
        repo_path = s.get("repoPath", "")
        if not repo_path.startswith("skills/"):
            continue
        dirname = repo_path.split("/")[-1]
        if dirname != s.get("name"):
            errors.append(
                f"[{gid}] {s.get('name')}: skills/ 下目录名应为 {s.get('name')}，实际 {dirname}"
            )

    result = {
        "repo": repo,
        "discovered": sorted(names),
        "discoveredCount": len(discovered),
        "manifestCount": len(manifest_entries),
        "errors": errors,
        "warnings": warnings,
        "ok": not errors,
    }

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"仓库: {repo}")
        print(f"运行时可发现技能: {len(discovered)} 个")
        print(f"manifest 登记技能: {len(manifest_entries)} 个")
        if warnings:
            print("\n警告:")
            for w in warnings:
                print(f"  ! {w}")
        if errors:
            print("\n错误:")
            for e in errors:
                print(f"  x {e}")
            print("\n校验失败")
        else:
            print("\n校验通过")

    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
