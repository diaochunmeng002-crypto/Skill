#!/usr/bin/env python3
"""List installed personal Codex skills with one concise purpose each."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8")


DEFAULT_REPO = "diaochunmeng002-crypto/Skill"
DEFAULT_REF = "main"
SKILL_META = {
    "ca": ("静态分析", "Code Analyze", "从入口整理完整调用链"),
    "ce": ("静态分析", "Code Entry", "找出阅读代码时应先看的关键结点"),
    "cb": ("调试", "Code Breakpoint", "根据断点清单操作 Visual Studio 断点"),
    "cbp": ("调试", "Code Breakpoint Planner", "根据目标和分析来源生成断点 manifest"),
    "cd": ("调试", "Code Debug", "分析启动入口并支持 --debugwait"),
    "ch": ("运行", "Code How to Run", "生成项目的最短运行说明"),
    "cm": ("管理", "Code Manual", "列出 Git 仓库与本机 skill 状态"),
}
GROUP_ORDER = ("静态分析", "调试", "运行", "管理", "其他")
SKILL_ORDER = {name: index for index, name in enumerate(SKILL_META)}


def default_skills_root() -> Path:
    codex_home = os.environ.get("CODEX_HOME")
    if codex_home:
        return Path(codex_home).expanduser() / "skills"
    return Path.home() / ".codex" / "skills"


def read_frontmatter(skill_file: Path) -> dict[str, str]:
    try:
        lines = skill_file.read_text(encoding="utf-8-sig").splitlines()
    except (OSError, UnicodeError):
        return {}

    if not lines or lines[0].strip() != "---":
        return {}

    values: dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if ":" not in line or line.startswith((" ", "\t")):
            continue
        key, value = line.split(":", 1)
        values[key.strip()] = value.strip().strip("\"'")
    return values


def first_sentence(text: str, limit: int = 72) -> str:
    cleaned = re.sub(r"\s+", " ", text).strip()
    if not cleaned:
        return "个人 skill"

    sentence = re.split(r"(?<=[。.!?])\s+|；", cleaned, maxsplit=1)[0]
    sentence = sentence.rstrip("。.!?")
    if len(sentence) > limit:
        sentence = sentence[: limit - 1].rstrip() + "…"
    return sentence


def format_skill(name: str, description: str) -> str:
    metadata = SKILL_META.get(name)
    if metadata:
        return f"{name.upper()}({metadata[1]}) — {metadata[2]}"
    return f"{name.upper()} — {description}"


def collect_local_skills(root: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    if not root.is_dir():
        return entries

    for directory in sorted(root.iterdir(), key=lambda item: item.name.lower()):
        if not directory.is_dir() or directory.name.startswith("."):
            continue
        skill_file = directory / "SKILL.md"
        if not skill_file.is_file():
            continue

        frontmatter = read_frontmatter(skill_file)
        name = frontmatter.get("name") or directory.name
        metadata = SKILL_META.get(name)
        entries[name] = (
            metadata[2]
            if metadata
            else first_sentence(frontmatter.get("description", ""))
        )
    return entries


def request_text(url: str, timeout: float) -> str:
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "cm-code-manual/1.0",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(url, headers=headers)
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8")


def fetch_github_catalog(
    repo: str, ref: str, timeout: float
) -> tuple[dict[str, str], str | None]:
    tree_url = (
        f"https://api.github.com/repos/{repo}/git/trees/"
        f"{quote(ref, safe='')}?recursive=1"
    )
    try:
        payload = json.loads(request_text(tree_url, timeout))
        paths = []
        for item in payload.get("tree", []):
            path = item.get("path", "")
            match = re.fullmatch(r"skills/([^/]+)/SKILL\.md", path)
            if match and not match.group(1).startswith("."):
                paths.append((match.group(1), path))
    except (HTTPError, URLError, OSError, ValueError, KeyError) as error:
        return {}, str(error)

    catalog: dict[str, str] = {}
    for name, path in sorted(paths):
        metadata = SKILL_META.get(name)
        if metadata:
            catalog[name] = metadata[2]
            continue

        raw_url = (
            f"https://raw.githubusercontent.com/{repo}/"
            f"{quote(ref, safe='/')}/{quote(path, safe='/')}"
        )
        try:
            frontmatter_text = request_text(raw_url, timeout)
            description = ""
            for line in frontmatter_text.splitlines():
                if line.startswith("description:"):
                    description = line.split(":", 1)[1].strip().strip("\"'")
                    break
            catalog[name] = first_sentence(description or "远端 skill")
        except (HTTPError, URLError, OSError, ValueError):
            catalog[name] = "远端 skill"
    return catalog, None


def load_catalog(
    catalog_root: Path | None, repo: str, ref: str, timeout: float, offline: bool
) -> tuple[dict[str, str], bool, str | None]:
    if catalog_root is not None:
        return collect_local_skills(catalog_root.expanduser()), True, None
    if offline:
        return {}, False, None
    catalog, error = fetch_github_catalog(repo, ref, timeout)
    return catalog, error is None, error


def skill_group(name: str) -> str:
    metadata = SKILL_META.get(name)
    return metadata[0] if metadata else "其他"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="List Git and local personal Codex skills in grouped form."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=default_skills_root(),
        help="skills directory (defaults to $CODEX_HOME/skills)",
    )
    parser.add_argument(
        "--catalog-root",
        type=Path,
        help="local directory used instead of the GitHub catalog",
    )
    parser.add_argument("--repo", default=DEFAULT_REPO, help="GitHub owner/repository")
    parser.add_argument("--ref", default=DEFAULT_REF, help="Git branch or tag")
    parser.add_argument("--timeout", type=float, default=6.0)
    parser.add_argument("--offline", action="store_true", help="skip GitHub lookup")
    arguments = parser.parse_args()

    local = collect_local_skills(arguments.root.expanduser())
    catalog, remote_available, remote_error = load_catalog(
        arguments.catalog_root,
        arguments.repo,
        arguments.ref,
        arguments.timeout,
        arguments.offline,
    )

    names = sorted(
        set(local) | set(catalog),
        key=lambda name: (SKILL_ORDER.get(name, 10_000), name.lower()),
    )
    if not names:
        print(f"No personal skills found in {arguments.root}", file=sys.stderr)
        return 1

    grouped: dict[str, list[tuple[str, str, str]]] = {
        group: [] for group in GROUP_ORDER
    }
    for name in names:
        if remote_available:
            if name in local and name in catalog:
                status = "[已装]"
            elif name in catalog:
                status = "[未装]"
            else:
                status = "[本地]"
        else:
            status = "[已装]"
        description = catalog.get(name) or local.get(name) or "个人 skill"
        grouped[skill_group(name)].append((name, description, status))

    first_group = True
    for group in GROUP_ORDER:
        entries = grouped[group]
        if not entries:
            continue
        if not first_group:
            print()
        first_group = False
        print(group)
        for name, description, status in entries:
            print(f"  {status} {format_skill(name, description)}")

    if remote_error:
        print(
            "提示：GitHub 索引不可用，仅显示本机 skill。",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
