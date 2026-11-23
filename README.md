# Skills

Personal collection of reusable Codex skills.

## Included skills

- **ca** — static whole-program call-stack analysis from the main entry point.
- **ce** — key-node code entry guide for learning a repository before tracing
  its full call stack.

## Structure

```text
Skills/
└── skills/
    └── <skill-name>/
        ├── SKILL.md
        ├── agents/
        ├── scripts/
        ├── references/
        └── assets/
```

Each skill lives in its own lowercase, hyphenated directory under `skills/`.
Only create optional resource directories when the skill actually uses them.

## Adding a skill

1. Create the skill with the `skill-creator` workflow.
2. Keep `SKILL.md` focused on the decisions and constraints that improve the
   requested workflow.
3. Validate the skill with `quick_validate.py`.
4. Commit the complete skill directory together with any required resources.

## Validation

Validate a skill directory before committing:

```powershell
python "$env:CODEX_HOME\skills\.system\skill-creator\scripts\quick_validate.py" `
  "<repo-root>\skills\<skill-name>"
```
