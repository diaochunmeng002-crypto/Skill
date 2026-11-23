---
name: cm
description: List personal Codex skills from the Git catalog, group them by purpose, and mark whether each skill is installed locally. Use when the user says "cm", "code manual", asks which personal skills exist, or wants a compact skill index. Do not list marketplace skills, expand full usage, or create a report file.
metadata:
  short-description: List personal skills one line each
---

# CM: Code Manual

Show a compact, grouped index of personal skills from the Git catalog and mark
their local installation status.

## Workflow

1. Run the bundled scanner from this skill's directory:

   ```bash
   python scripts/list-skills.py
   ```

2. Return its output with no additional heading and no extra prose.
3. One skill must occupy exactly one line. Use simple groups by purpose:

   ```text
   静态分析
     [已装] ca  从入口整理完整调用链
     [未装] ce  找出阅读代码时应先看的关键结点
   ```

4. Use these status markers:
   - `[已装]`: present in both the Git catalog and the local skills directory.
   - `[未装]`: present in Git but absent locally.
   - `[本地]`: present locally but absent from Git.

5. Stop after the list unless the user asks about a specific skill. A follow-up
   may expand only the requested entry.

## Scope

- Read installed skills from `$CODEX_HOME/skills`, or `~/.codex/skills` when
  `CODEX_HOME` is unset.
- Read the Git catalog from `diaochunmeng002-crypto/Skill` on `main` by default.
- Use `GITHUB_TOKEN` or `GH_TOKEN` automatically when present.
- Exclude `.system` and other hidden directories by default.
- Do not invoke `skill-installer` and do not list curated or marketplace skills.
- Do not create or update files.
- If GitHub is unavailable, list local skills and emit one short warning.
- Group known skills as `静态分析`, `调试`, `运行`, or `管理`; put unknown skills
  under `其他`.
- Keep descriptions short and concrete. Prefer what the skill does, not trigger
  words or implementation details.
- If a newly installed unknown skill is found, compress its frontmatter
  description to one sentence.
