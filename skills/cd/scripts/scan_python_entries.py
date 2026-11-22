#!/usr/bin/env python3
"""Find likely runtime entry points in a Python project for code-debug setup.

The scan is intentionally static. It does not import project code or install
dependencies, so results are candidates that must be checked against the
project's actual launch configuration.
"""

from __future__ import annotations

import argparse
import ast
import configparser
import json
import os
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - Python < 3.11 fallback
    try:
        import tomli as tomllib
    except ModuleNotFoundError:
        tomllib = None  # type: ignore[assignment]


IGNORED_DIRECTORIES = {
    ".git",
    ".hg",
    ".mypy_cache",
    ".nox",
    ".pytest_cache",
    ".ruff_cache",
    ".svn",
    ".tox",
    ".venv",
    "__pycache__",
    "build",
    "dist",
    "env",
    "node_modules",
    "site-packages",
    "venv",
}
TEST_DIRECTORIES = {"test", "tests", "testing"}
LAUNCH_FILE_NAMES = {
    "compose.yaml",
    "compose.yml",
    "docker-compose.yaml",
    "docker-compose.yml",
    "Dockerfile",
    "Justfile",
    "Makefile",
    "Procfile",
    "Taskfile.yaml",
    "Taskfile.yml",
}
SERVICE_PATTERNS = (
    ("asgi-server", re.compile(r"\b(?:uvicorn|hypercorn|daphne)\b", re.IGNORECASE)),
    ("wsgi-server", re.compile(r"\b(?:gunicorn|waitress-serve)\b", re.IGNORECASE)),
    (
        "framework-server",
        re.compile(
            r"\b(?:flask\s+run|django-admin\s+runserver|streamlit\s+run)\b",
            re.IGNORECASE,
        ),
    ),
)
PYTHON_MODULE_COMMAND = re.compile(
    r"\bpython(?:3(?:\.\d+)?)?\s+-m\s+([A-Za-z_][\w.]*)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Entry:
    kind: str
    evidence: str
    target: str | None = None
    source: str | None = None
    line: int | None = None
    role_hint: str = "cli-or-service"


class Scanner:
    def __init__(self, root: Path, include_tests: bool) -> None:
        self.root = root.resolve()
        self.include_tests = include_tests
        self.entries: list[Entry] = []
        self.warnings: list[str] = []
        self._seen: set[tuple[str, str | None, str | None, int | None]] = set()
        self._source_roots = [self.root]
        src_root = self.root / "src"
        if src_root.is_dir():
            self._source_roots.append(src_root)

    def scan(self) -> None:
        self._scan_pyproject()
        self._scan_setup_cfg()
        self._scan_setup_py()
        self._scan_python_sources()
        self._scan_launch_files()

    def _add(self, entry: Entry) -> None:
        key = (entry.kind, entry.target, entry.source, entry.line)
        if key not in self._seen:
            self._seen.add(key)
            self.entries.append(entry)

    def _relative(self, path: Path) -> str:
        try:
            return path.resolve().relative_to(self.root).as_posix()
        except ValueError:
            return path.as_posix()

    def _iter_files(self) -> Iterable[Path]:
        for current, directories, files in os.walk(self.root):
            current_path = Path(current)
            directories[:] = sorted(
                directory
                for directory in directories
                if directory.lower() not in IGNORED_DIRECTORIES
                and (
                    self.include_tests
                    or directory.lower() not in TEST_DIRECTORIES
                )
            )
            for filename in sorted(files):
                if not self.include_tests and filename.lower().startswith("test_"):
                    continue
                yield current_path / filename

    def _scan_pyproject(self) -> None:
        path = self.root / "pyproject.toml"
        if not path.is_file():
            return
        if tomllib is None:
            self.warnings.append(
                "pyproject.toml was not parsed because tomllib/tomli is unavailable"
            )
            return
        try:
            data = tomllib.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError) as error:
            self.warnings.append(f"could not parse pyproject.toml: {error}")
            return

        project = data.get("project", {})
        if isinstance(project, dict):
            self._add_script_table(
                project.get("scripts"), "console-script", "project.scripts"
            )
            self._add_script_table(
                project.get("gui-scripts"), "gui-script", "project.gui-scripts"
            )

        tool = data.get("tool", {})
        if isinstance(tool, dict):
            poetry = tool.get("poetry", {})
            if isinstance(poetry, dict):
                self._add_script_table(
                    poetry.get("scripts"), "console-script", "tool.poetry.scripts"
                )
            pdm = tool.get("pdm", {})
            if isinstance(pdm, dict):
                self._add_commands(
                    pdm.get("scripts"), "task-script", "tool.pdm.scripts"
                )

    def _add_script_table(
        self, table: Any, kind: str, evidence_prefix: str
    ) -> None:
        if not isinstance(table, dict):
            return
        for name, value in table.items():
            if isinstance(value, str):
                self._add_entry(
                    kind=kind,
                    target=value,
                    evidence=f"pyproject.toml [{evidence_prefix}].{name}",
                )

    def _add_commands(self, value: Any, kind: str, evidence: str) -> None:
        for command in flatten_strings(value):
            self._add(
                Entry(
                    kind=kind,
                    target=command,
                    evidence=evidence,
                    role_hint=classify_command(command),
                )
            )

    def _add_entry(self, kind: str, target: str, evidence: str) -> None:
        source, line = self._resolve_target(target)
        self._add(
            Entry(
                kind=kind,
                target=target,
                evidence=evidence,
                source=source,
                line=line,
                role_hint=classify_target(target, source),
            )
        )

    def _scan_setup_cfg(self) -> None:
        path = self.root / "setup.cfg"
        if not path.is_file():
            return
        parser = configparser.ConfigParser(interpolation=None)
        parser.optionxform = str
        try:
            with path.open(encoding="utf-8") as source_file:
                parser.read_file(source_file)
        except (OSError, UnicodeError, configparser.Error) as error:
            self.warnings.append(f"could not parse setup.cfg: {error}")
            return

        section = parser["options.entry_points"] if parser.has_section(
            "options.entry_points"
        ) else None
        if section is None:
            return
        for option, kind in (
            ("console_scripts", "console-script"),
            ("gui_scripts", "gui-script"),
        ):
            if not section.get(option):
                continue
            for name, target in parse_entry_point_lines(section.get(option, "")):
                self._add_entry(
                    kind=kind,
                    target=target,
                    evidence=f"setup.cfg [options.entry_points].{option}.{name}",
                )

    def _scan_setup_py(self) -> None:
        path = self.root / "setup.py"
        if not path.is_file():
            return
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        except (OSError, UnicodeError, SyntaxError) as error:
            self.warnings.append(f"could not parse setup.py: {error}")
            return

        constants: dict[str, Any] = {}
        for node in tree.body:
            if isinstance(node, (ast.Assign, ast.AnnAssign)):
                value_node = node.value
                if value_node is None:
                    continue
                try:
                    value = ast.literal_eval(value_node)
                except (ValueError, TypeError):
                    continue
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                for target in targets:
                    if isinstance(target, ast.Name):
                        constants[target.id] = value

        for node in ast.walk(tree):
            if not isinstance(node, ast.Call) or not is_setup_call(node.func):
                continue
            for keyword in node.keywords:
                if keyword.arg != "entry_points":
                    continue
                value = literal_value(keyword.value, constants)
                self._add_setup_entry_points(value)

    def _add_setup_entry_points(self, value: Any) -> None:
        if isinstance(value, str):
            for name, target in parse_entry_point_lines(value):
                self._add_entry(
                    kind="console-script",
                    target=target,
                    evidence=f"setup.py entry_points.{name}",
                )
            return
        if not isinstance(value, dict):
            return
        for group, group_value in value.items():
            if group not in {"console_scripts", "gui_scripts"}:
                continue
            kind = "gui-script" if group == "gui_scripts" else "console-script"
            text = "\n".join(flatten_strings(group_value))
            for name, target in parse_entry_point_lines(text):
                self._add_entry(
                    kind=kind,
                    target=target,
                    evidence=f"setup.py entry_points.{group}.{name}",
                )

    def _scan_python_sources(self) -> None:
        for path in self._iter_files():
            if path.suffix.lower() != ".py":
                continue
            relative = self._relative(path)
            if path.name == "__main__.py":
                self._add(
                    Entry(
                        kind="package-main",
                        source=relative,
                        line=1,
                        evidence="Python package __main__.py",
                    )
                )
            try:
                text = path.read_text(encoding="utf-8")
                tree = ast.parse(text, filename=str(path))
            except (OSError, UnicodeError, SyntaxError) as error:
                self.warnings.append(f"could not parse {relative}: {error}")
                continue

            for node in tree.body:
                if isinstance(node, ast.If) and is_main_guard(node.test):
                    self._add(
                        Entry(
                            kind="main-guard",
                            source=relative,
                            line=node.lineno,
                            evidence="if __name__ == '__main__'",
                        )
                    )

            for line_number, line in enumerate(text.splitlines(), start=1):
                role_hint = classify_command(line)
                stripped = line.strip()
                if (
                    role_hint == "service"
                    and stripped
                    and not stripped.startswith(("#", "from ", "import "))
                ):
                    self._add(
                        Entry(
                            kind="service-bootstrap",
                            source=relative,
                            line=line_number,
                            evidence=stripped,
                            role_hint="service",
                        )
                    )

    def _scan_launch_files(self) -> None:
        for path in self._iter_files():
            relative = self._relative(path)
            if not is_launch_file(path, relative):
                continue
            try:
                lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError as error:
                self.warnings.append(f"could not read {relative}: {error}")
                continue
            for line_number, line in enumerate(lines, start=1):
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                module_match = PYTHON_MODULE_COMMAND.search(line)
                server_role = classify_command(line)
                if module_match:
                    self._add(
                        Entry(
                            kind="launch-hint",
                            target=f"python -m {module_match.group(1)}",
                            source=relative,
                            line=line_number,
                            evidence=stripped,
                            role_hint=server_role,
                        )
                    )
                elif server_role == "service":
                    self._add(
                        Entry(
                            kind="launch-hint",
                            source=relative,
                            line=line_number,
                            evidence=stripped,
                            role_hint="service",
                        )
                    )

    def _resolve_target(self, target: str) -> tuple[str | None, int | None]:
        module_name = target.split(":", 1)[0].strip()
        attributes = target.split(":", 1)[1].strip() if ":" in target else ""
        module_parts = module_name.split(".")
        if not module_name or not all(part.isidentifier() for part in module_parts):
            return None, None

        for base in self._source_roots:
            module_file = base.joinpath(*module_parts).with_suffix(".py")
            package_file = base.joinpath(*module_parts, "__init__.py")
            path = module_file if module_file.is_file() else package_file
            if not path.is_file():
                continue
            relative = self._relative(path)
            line = find_attribute_line(path, attributes)
            return relative, line
        return None, None


def flatten_strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for nested in value.values():
            yield from flatten_strings(nested)
    elif isinstance(value, (list, tuple)):
        for nested in value:
            yield from flatten_strings(nested)


def parse_entry_point_lines(value: str) -> Iterable[tuple[str, str]]:
    for line in value.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        name, target = stripped.split("=", 1)
        if name.strip() and target.strip():
            yield name.strip(), target.strip()


def literal_value(node: ast.AST, constants: dict[str, Any]) -> Any:
    if isinstance(node, ast.Name) and node.id in constants:
        return constants[node.id]
    try:
        return ast.literal_eval(node)
    except (ValueError, TypeError):
        return None


def is_setup_call(node: ast.expr) -> bool:
    if isinstance(node, ast.Name):
        return node.id == "setup"
    return isinstance(node, ast.Attribute) and node.attr == "setup"


def is_main_guard(node: ast.expr) -> bool:
    if not isinstance(node, ast.Compare) or len(node.ops) != 1:
        return False
    if not isinstance(node.ops[0], ast.Eq):
        return False
    sides = (node.left, node.comparators[0])
    return any(
        isinstance(side, ast.Name) and side.id == "__name__"
        for side in sides
    ) and any(
        isinstance(side, ast.Constant) and side.value == "__main__"
        for side in sides
    )


def find_attribute_line(path: Path, attributes: str) -> int | None:
    if not attributes:
        return None
    first_attribute = attributes.split(".", 1)[0]
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    except (OSError, UnicodeError, SyntaxError):
        return None
    for node in tree.body:
        if isinstance(
            node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)
        ) and node.name == first_attribute:
            return node.lineno
    return None


def classify_command(command: str) -> str:
    for _, pattern in SERVICE_PATTERNS:
        if pattern.search(command):
            return "service"
    return "cli-or-service"


def classify_target(target: str, source: str | None) -> str:
    if classify_command(target) == "service":
        return "service"
    name = Path(source).name.lower() if source else ""
    if name in {"asgi.py", "wsgi.py"} or "server" in name:
        return "service"
    return "cli-or-service"


def is_launch_file(path: Path, relative: str) -> bool:
    if path.name in LAUNCH_FILE_NAMES:
        return True
    if path.suffix.lower() in {".sh", ".ps1"}:
        return True
    parts = Path(relative).parts
    return len(parts) >= 3 and parts[0] == ".github" and parts[1] == "workflows"


def format_entry(index: int, entry: Entry) -> str:
    headline = f"{index}. [{entry.kind}]"
    if entry.target:
        headline += f" {entry.target}"
    elif entry.source:
        headline += f" {entry.source}"

    details: list[str] = []
    if entry.source:
        location = entry.source
        if entry.line is not None:
            location += f":{entry.line}"
        details.append(f"location: {location}")
    if entry.role_hint != "cli-or-service":
        details.append(f"role hint: {entry.role_hint}")
    details.append(f"evidence: {entry.evidence}")
    return headline + "".join(f"\n   {detail}" for detail in details)


def run(root_argument: str, as_json: bool, include_tests: bool) -> int:
    root = Path(root_argument)
    if not root.is_dir():
        print(f"error: project root is not a directory: {root}", file=sys.stderr)
        return 2

    scanner = Scanner(root, include_tests)
    scanner.scan()

    if as_json:
        payload = {
            "root": str(scanner.root),
            "entries": [asdict(entry) for entry in scanner.entries],
            "warnings": scanner.warnings,
        }
        json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
        return 0

    print(f"Python entry candidates for {scanner.root}:")
    if not scanner.entries:
        print("  (none found)")
    for index, entry in enumerate(scanner.entries, start=1):
        print(format_entry(index, entry))
    if scanner.warnings:
        print("\nWarnings:")
        for warning in scanner.warnings:
            print(f"  - {warning}")
    print(
        "\nStatic scan only: verify the effective process against the project's "
        "actual launch command before editing."
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Find likely Python CLI and service entry points."
    )
    parser.add_argument("project_root", nargs="?", default=".")
    parser.add_argument("--json", action="store_true", help="emit JSON")
    parser.add_argument(
        "--include-tests",
        action="store_true",
        help="include test directories and test_*.py files",
    )
    arguments = parser.parse_args()
    return run(arguments.project_root, arguments.json, arguments.include_tests)


if __name__ == "__main__":
    raise SystemExit(main())
