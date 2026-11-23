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
   - Prefer putting each explanation on the same line as its call:
     `[call]  # explanation`.
   - Align `#` within a contiguous sibling group at a common display column.
     Use at least two spaces before `#`; prefer the next multiple-of-four tab
     stop after the normal call width.
   - Count CJK characters as two display columns. Do not let one exceptionally
     wide call shift the alignment column for the whole group.
   - Target a maximum report width of about 100 display columns. When a call is
     too wide, or the aligned explanation would exceed that width, put the
     explanation on the next line with two extra spaces and a `#` prefix.
   - Keep one explanation per call. If it does not fit comfortably beside the
     call, shorten it instead of creating a long right-hand column.
   - Omit obvious telemetry/logging-only lines by default:
     - Examples: `active_logger.log(...)`, `logger.log(...)`, metric counters, tracing spans.
     - Replace with a single collapsed note only when it helps: `logging (omitted)`.
     - Include these lines only if the user explicitly asks: "包含日志/不要忽略 log/保留 telemetry".

4. Add state/data-flow notes where useful:
   - Show where key state fields are created, formatted, passed, mutated, or consumed.
   - For agent/LLM systems, explicitly identify prompt construction, model invocation, tool execution, retry, guardrail, routing, and termination points.
   - Apply the same inline-comment rule to state variables, flow arrows, config
     keys, and other report items. Do not revert to block-style comments just
     because the item name is short.
   - In a `[关键状态流]` or similar section, align `#` within that group even
     when the preceding items use `->` instead of a stack-style node.

5. Write the final output file:
   - Use the workspace root.
   - Filename format must be `ca_yyyyMMdd_HHmmss.txt`.
   - Include a final note section explaining what the static analysis can prove and what requires runtime trace/debugger evidence.

## Output Format

Use this structure:

```text
[entry point]                    # 程序入口 / main entry
[parent function]                # 阶段说明
  [important child call]         # 说明这个调用做什么
  [another child call]           # 说明这个调用做什么
  [a child call that is too wide to annotate inline]
    # 宽行回退：说明放在下一行，避免右侧注释被推到很远。

[关键状态流]
  abs_fnames                    # 可编辑文件；进入 chat_files 和 repo map。
  abs_read_only_fnames          # 只读文件；进入 readonly_files。
  cur_messages                  # 当前轮消息；发送前后分别追加 user/assistant。
  done_messages                 # 历史消息；经 ChatSummary 压缩。
  ChatChunks                    # 顺序：system、examples、files、done、reminder。
  partial_response_content      # 当前模型回复；流式与非流式最终都写入这里。

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
- Keep report items and call lines compact.
- Prefer inline `#` explanations over block-style comments.
- Apply inline alignment to every block type: calls, state variables, flow
  arrows, configuration entries, and summary items.
- Align comments in nearby sibling lines within the same section and indentation
  level, but do not chase alignment across unrelated sections or branches.
- Cap alignment columns around 48 display columns. Long calls use the next-line
  fallback instead of pushing all comments to the right.
- Keep descriptions short. If an inline description would make the line awkward,
  put it on the following line rather than shrinking the gap or wrapping the
  call line.
- Avoid a raw debugger-style dump unless the user explicitly asks for it.
- If runtime behavior is inferred from framework conventions, label it as inferred.
- If exact runtime line numbers from third-party libraries are needed, ask the user for a runtime call stack, trace, or debugger capture.
