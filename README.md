# Skills

Personal collection of reusable Codex skills.

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
python C:\Users\diaochunmeng\.codex\skills\.system\skill-creator\scripts\quick_validate.py `
  C:\Code\AI\Skills\skills\<skill-name>
```
