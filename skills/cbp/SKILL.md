---
name: cbp
description: Plan a small, goal-driven breakpoint manifest from ca/ce analysis reports and source code for later application by cb. Use when the user says "cbp", "code breakpoint planner", asks where to set breakpoints, or needs breakpoint candidates from an analysis report. Do not apply breakpoints, and do not proceed without an explicit ca or ce source.
metadata:
  short-description: Plan breakpoint manifests from analysis
---

# CBP: Code Breakpoint Planner

Turn a debugging goal and existing analysis reports into a small manifest that
`cb` can apply to Visual Studio.

## Required Inputs

Before doing any planning, require both:

1. A concrete debugging goal.
2. At least one explicit source labeled `ca=<path>` or `ce=<path>`.

`cd=<path>` and `ch=<path>` may provide useful context, but cannot replace the
required `ca` or `ce` source.

If a source is missing, stop and return:

```text
错误：cbp 至少需要一个 ca 或 ce 分析来源。
请提供 ca=<文件路径> 或 ce=<文件路径>，并说明要排查的调试目标。
```

Do not infer a source merely because a file is nearby, recent, or named
`study/*.txt`. Verify that each declared source exists before planning.

Examples:

```text
$cbp goal="tool call not triggered" ca=study/ca_20261124_101500.txt
$cbp goal="model request never returns" \
  ca=study/ca_20261124_101500.txt \
  ce=study/ce_20261124_102000.txt
```

## Workflow

1. Read the debugging goal and every declared source.
2. Extract only evidence relevant to that goal:
   - entry and control-flow positions from `ca`;
   - key nodes, boundaries, and configuration points from `ce`;
   - optional runtime information from `cd` or `ch`.
3. Inspect the referenced source lines before selecting a breakpoint. Never
   copy a line number that is missing, stale, or points only at a declaration.
4. Form one to three debugging hypotheses. Group candidate breakpoints by those
   hypotheses.
5. Select 5–15 executable positions. Prefer a few high-signal boundaries over
   every frame in the call chain.
6. Write the manifest and stop. Do not connect to Visual Studio and do not call
   `cb` unless the user separately asks to apply the result.

## Output

Default output path:

```text
<workspace>/study/cbp_yyyyMMdd_HHmmss.manifest
```

Create `study/` when needed. Honor an explicit output path. Do not overwrite an
existing manifest.

Manifest format:

```text
# CBP breakpoint plan
# Goal: <debugging goal>
# Sources:
#   ca=<relative or absolute path>
#   ce=<relative or absolute path>
# Generated: <timestamp>

[Entry]
# 确认入口已执行，以及调试门控前后的状态。
src/main.py:42

[ToolLoop]
# 确认工具调用是否进入执行分支。
src/agent/tools.py:158
src/agent/tools.py:174

[FailurePath]
# 确认异常是否被转换或提前吞掉。
src/agent/runtime.py:233
```

Rules:

- Paths are relative to the source root used by `cb`.
- Section names should describe a hypothesis or subsystem.
- Put a short `#` explanation before a group of related breakpoints.
- Use executable statements, not function/class signature lines.
- Keep the default plan at 5–15 breakpoints.
- Do not include tests unless the user explicitly requests test debugging.
- Mark an unverified candidate as `未确认`; do not present it as exact evidence.

After writing the file, report:

- manifest path;
- number of breakpoints and sections;
- source reports used;
- any unverified candidates;
- that `cb` is required to apply the manifest.
