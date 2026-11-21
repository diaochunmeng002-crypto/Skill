---
name: ce
description: Code entry - key-node static analysis for learning a codebase (not a full call stack). Find and list entry/config/bootstrap and other first-read nodes, each with a one-sentence explanation and a clickable link. Use when the user says ce, code entry, 关键节点, 关键路径, 架构节点, 入口/配置/路由/DI/数据访问/异常处理, ca2 (legacy), or asks "给我一套点位去分析代码". Contrast ca = mainline call-stack trace; ce = where to enter and read first.
---

# CE: Code Entry

## Purpose

Statically scan a codebase and output a small set of **key nodes**（关键结点）– the doors into understanding the repo（入口 / 配置 / 编排等）– each with:

- **one-sentence explanation**（一句话说明）
- **a link** to the exact source location（最好带上链接）

This skill does **not** try to build a full program call stack (use **ca** for that). It focuses on "where to look" and "why it matters".

## Workflow

1. Find the project type and run entry hints (minimal reads):
   - Prefer explicit user context (language/framework/repo).
   - Otherwise inspect: README run commands, build scripts, package manifests, solution/project files, typical entry files.
   - Do not read or edit files whose name or path contains `test` unless the user directly asks (case-insensitive).

2. Identify key-node categories and locate candidates:
   - **Entry / Bootstrapping**: program entry, host builder, app initialization.
   - **Configuration**: config loading, env/secret overlay, feature flags.
   - **Dependency Injection / Service registration**: container setup, module registration.
   - **Routing / Endpoints / Message handlers**: HTTP routes, RPC handlers, event/queue consumers.
   - **Core domain orchestration**: main "use case" coordinator / service / workflow engine.
   - **Data access**: DB context, repositories, query layer, migrations, storage clients.
   - **External integrations**: HTTP clients, SDK wrappers, retry/policy, serialization contracts.
   - **Error handling & resilience**: global exception handlers, retry/circuit breaker, fallback.
   - **Observability**: logging bootstrap, tracing/metrics initialization (only as key nodes, not verbose).
   - **Security** (if present): authn/authz middleware, token validation, permission checks.

3. Deduplicate and keep the list small:
   - Default target: **8-15 nodes**.
   - Prefer "one file/function that unlocks a whole area" over many small nodes.
   - If multiple implementations exist, pick the one wired in the default runtime path; mention alternates briefly.

4. Write output file to workspace root:
   - Filename:

```text
STUDY.md
```

## Output Format

Use this structure:

```text
# How to use
示例（你只要这样问即可）：
- "ce: 帮我扫一下这个仓库的关键结点，输出到 STUDY.md"
- "ce: 只要主线链路 5 个关键结点，带链接"

== 关键结点清单（key nodes） ==

1) [Node name] — 一句话说明
   - Link: <clickable link>

2) ...
...

备注
- 这份清单能帮助你快速定位“入口/配置/路由/核心编排/数据访问/集成/异常处理”等关键位置。
- 这是静态扫描；若存在运行时反射/插件/动态路由，需结合运行日志/断点再确认。
```

### Link Rules

Prefer links in this order:

1. **Code reference link**: `relative/path:lineStart-lineEnd` (best when exact lines are known)
2. **File link**: `relative/path` (when line ranges are unclear)
3. **Doc link**: a URL (when node is defined by external config/doc)

If the environment supports clickable file links, include both:
- `relative/path:lineStart-lineEnd`
- `relative/path`

## How to Decide "Key"

A node is "key" if it answers at least one of:

- Where does the app start and what gets initialized?
- Where is configuration loaded and overridden?
- Where are routes/handlers registered?
- Where is the core business workflow orchestrated?
- Where does data enter/leave (DB/HTTP/queue/files)?
- Where are errors handled and retried?
- Where are auth checks enforced?

## Scope Control

- If user asks "精简/只要入口到核心/5个点": output **5-7** nodes, only the mainline.
- If user asks "全量/想覆盖所有模块": output **15-30** nodes grouped by module, still no call-stack.

## Style Rules

- Prefer Chinese one-liners if the user is using Chinese.
- One node = one sentence. If it can't fit, split into two short sentences max.
- Be honest: mark uncertain wiring as "推测/可能" and say what to verify at runtime.
- Avoid adding code comments; the output is a reading guide, not code changes.
