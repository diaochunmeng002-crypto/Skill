---
name: ca
description: Static code analysis from the main entry point to produce a readable whole-program call stack. Use when the user says ca, code analyze, 静态分析调用栈, 从 main 入口分析, 整理调用链, or asks to output ca_年月日时分秒.txt.
---

# CA: Code Analyze

## Purpose

Analyze code statically from the program entry point, merge and optimize the discovered call flow, and write a readable call stack summary to the workspace root as:

```text
ca_yyyyMMdd_HHmmss.txt
```

Example:

```text
ca_20260605_193000.txt
```

## Workflow

1. Identify the workspace root and likely entry point:
   - Prefer explicit user input if provided.
   - Otherwise inspect common entry files such as `Program.cs`, `Main`, `__main__.py`, `cli.py`, `main.py`, `app.py`, package scripts, project files, or README run commands.
   - Do not read or edit files whose name or path contains `test` unless the user directly asks.

2. Trace the static call flow from the entry point:
   - Follow direct calls first.
   - Include important framework registration calls, graph/build pipeline calls, dependency setup, tool registration, router/edge registration, and runtime invocation calls.
   - For dynamic framework behavior, distinguish source-confirmed calls from inferred runtime behavior.
   - Default output scope: fully expand the repository's own code along the mainline path.
     - Main entry: the default CLI/program entry that most users run.
     - Mainline path: the path that reaches the core runtime loop (e.g., agent build -> run -> model/tool loop), excluding optional branches unless requested.
     - Third-party libraries stay folded to key API call points only (see "Scope Control").

3. Merge and optimize the call stack:
   - Group repeated parent call sites under one parent function.
   - Do not keep noisy repeated lines like `cli.main : 84`, `cli.main : 85`, `cli.main : 94` if the useful information is the child action.
   - Keep meaningful child actions like `load_dotenv`, `build_parser`, `from_env`, `bind_tools`, `add_node`, `add_conditional_edges`, `invoke`, `llm_call`, and router functions.
   - Use indentation to represent call depth.
   - Do not create a right-hand aligned description column; mixed Chinese/English text and editor font settings make it visually unstable.
   - Put explanations on the next line with one extra indent and a `#` prefix.
   - Omit obvious telemetry/logging-only lines by default:
     - Examples: `active_logger.log(...)`, `logger.log(...)`, metric counters, tracing spans.
     - Replace with a single collapsed note only when it helps: `logging (omitted)`.
     - Include these lines only if the user explicitly asks: "包含日志/不要忽略 log/保留 telemetry".

4. Add state/data-flow notes where useful:
   - Show where key state fields are created, formatted, passed, mutated, or consumed.
   - For agent/LLM systems, explicitly identify prompt construction, model invocation, tool execution, retry, guardrail, routing, and termination points.

5. Write the final output file:
   - Use the workspace root.
   - Filename format must be `ca_yyyyMMdd_HHmmss.txt`.
   - Include a final note section explaining what the static analysis can prove and what requires runtime trace/debugger evidence.

## Output Format

Use this structure:

```text
[entry point]
  # 程序入口 / main entry
[parent function]
  # 阶段说明
  [important child call]
    # 说明这个调用做什么
  [important child call]
    # 说明这个调用做什么

总备注：这份静态调用链能证明什么，不能证明什么
能证明：
  - ...
不能证明：
  - ...
```

## Scope Control (Default vs Detailed)

Default behavior (完全展开):
- Expand the repository's own code along the main entry -> mainline path.
- Keep third-party libraries folded to key API call points only (no internal frames/line numbers).
- Still omit optional branches/alternate entry points unless the user asks for them.

If the user asks for "精简/主线路径/摘要/只要主入口主线路径":
- Collapse details to a minimal mainline summary (only the key calls needed to explain plan/prompt/model/tool/routing/termination).

If the user asks for "全量/详细/包含分支/包含备用入口/包含所有 flags/包含所有 provider/tools":
- Expand to include alternate entry points, optional modes, and the branch structure.
- Include provider/tool registration details and per-domain plan steps if relevant.

If the user asks for "完全展开":
- Expand all code paths for the repository's own code under the mainline path.
- Keep third-party libraries folded to key API call points only (do not expand their internal call stacks):
  - `langgraph`: `StateGraph(...)`, `add_node/add_edge/add_conditional_edges`, `compile`, `ToolNode(...)`, `app.invoke(...)`
  - `langchain/openai`: `ChatOpenAI(...)`, `bind_tools(...)`, `model.invoke(...)`
- When a third-party call is important, include it as a single leaf line with a short note, but do not enumerate internal frames/line numbers.

## Style Rules

- Prefer Chinese explanations if the user is using Chinese.
- Keep call lines compact.
- Prefer block-style explanations over alignment columns:
  - Good: call line first, then a next-line `# explanation` with one extra indent.
  - Avoid: padding spaces to align a right-hand description column.
- Keep descriptions short; if the description is longer than one line, split it into multiple `#` lines.
- Avoid a raw debugger-style dump unless the user explicitly asks for it.
- If runtime behavior is inferred from framework conventions, label it as inferred.
- If exact runtime line numbers from third-party libraries are needed, ask the user for a runtime call stack, trace, or debugger capture.
