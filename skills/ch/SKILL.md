---
name: ch
description: Create a concise, executable runbook for an existing source checkout, separating one-time setup from repeat launch commands across CLI, service, web, worker, or Docker modes. Use when the user says "ch", "code how to run", asks how to start a project, or wants a short runbook in a text file. Do not use for call-stack analysis or breakpoint setup.
metadata:
  short-description: Create concise project run instructions
---

# CH: Code How to Run

Produce a short, executable runbook. The result should answer only:

1. What must be installed or configured?
2. What command starts each supported mode?
3. Where is the project opened or accessed?
4. Which source files prove the commands?

Do not analyze the call stack, explain architecture, list every dependency, or
start the application unless the user explicitly asks for execution.

## Existing-checkout default

- Start from the current source checkout and its declared commands. Do not lead
  with a standalone installer when the repository, environment, or installed
  command already exists.
- Separate one-time setup from repeat operation:
  - one-time: dependency installation, environment/config creation, Docker build;
  - repeat: application start, service start, and `docker run`.
- Put shared dependency installation and persistent configuration under one
  `[首次配置]` section. If one superset installation supports several modes,
  install it once there and omit duplicate installation from those mode sections.
- If setup is already complete, omit installation entirely and show only the
  repeat launch command.
- Inspect local environment/config files when they materially affect startup.
  Report their path and variable names, but never print secret values.
- A persistent `.env` or equivalent config is first-time configuration, not a
  repeat launch step. State when an existing value is inherited from the
  machine environment rather than stored literally in the file.
- Treat `docker build` as one-time and `docker run` as every launch. Do not
  assume `docker --env-file` expands shell-style `${VAR}` references; pass
  referenced host values with `-e`, or use a literal values file.

## Output File

Write to:

```text
<workspace>/study/ch_yyyyMMdd_HHmmss.txt
```

- Create `study/` when needed.
- Generate the timestamp from the current local time.
- Do not overwrite an existing report.
- Honor an explicit output path from the user.
- Default to at most 50 lines. Expand only when there are many required startup
  modes or ordering constraints.

## Workflow

1. Identify the workspace root and project type from a small set of authoritative
   files:
   - README and developer-facing docs;
   - package/build manifests such as `pyproject.toml`, `package.json`,
     `Cargo.toml`, `go.mod`, solution/project files, or build scripts;
   - task-runner files, Dockerfiles, Compose files, Procfile, and CI commands.
   - root-local env/config files when they control startup.
   Prefer commands the project explicitly declares over inferred alternatives.

2. Identify launch modes. Common headings are:
   - `[CLI]`
   - `[Service]`
   - `[Web]`
   - `[Worker]`
   - `[Docker]`

   Keep separate headings when the commands, entry points, ports, environment, or
   working directories differ. Do not merge CLI and service into one block.

3. Resolve the minimum command details:
   - installation command;
   - required working directory;
   - exact start command;
   - required environment variables or config file;
   - host and port for services;
   - required dependency or startup order;
   - one source path or manifest line proving the command.
   - whether each step is one-time or required on every launch.

4. Mark confidence honestly:
   - Write commands confirmed from project files directly.
   - Mark inferred commands as `推断`.
   - Write `未确认` for unknown ports, credentials, or startup prerequisites
     instead of inventing them.

5. Write the report and stop. Do not include code excerpts, call flows, module
   inventories, or tutorial prose.

## Output Format

```text
<Project> 运行方式
环境：<language/runtime and important version>
工作目录：<workspace root>

[首次配置]
安装：<one-time dependency or setup command>
配置：<persistent env/config file and non-secret key names>
说明：<already completed behavior or required key source>
依据：<manifest/config/source paths>

[CLI]
启动：<command>
参数：<only required or representative flags>
入口：<file or module:function>
访问：<terminal or expected output>
依据：<relative/source/path:line or manifest section>

[Service]
启动：<command>
访问：<http://host:port or 未确认>
依赖：<required service/startup order, or 无>
入口：<source entry>
依据：<relative/source/path:line>

[Web]
启动：<command>
访问：<http://host:port or 未确认>
依赖：<shared setup already covered above, or mode-specific dependency>
依据：<source entry and config paths>

[Docker CLI]
首次构建：<build command>
启动：<docker run command for every launch>
访问：<terminal>
依据：<Dockerfile or Compose file>

[Docker Web]
首次构建：<build command for browser-capable target>
启动：<docker run command for every launch>
端口：<mapping or 未确认>
依据：<Dockerfile or Compose file>

[备注]
- <only a critical caveat>
- <only a critical caveat>
```

Omit empty sections. Keep one command per line. Put multi-step commands in
execution order. Repeat installation only when a mode uses a genuinely different
environment or dependency set.

## Scope Rules

- Do not scan or modify files whose names or paths contain `test` unless the user
  explicitly requests a test-running guide.
- Do not install dependencies, build images, or start long-running services just
  to produce the document.
- A safe help or version command may be run only when it materially improves
  confidence and has no meaningful side effects.
- If CLI and service share installation but differ in launch flags, repeat only
  the launch command in each section.
- If a service has multiple processes, list them in startup order under one
  `[Service]` section.
- Do not present an installer for users who already have the source checkout
  unless installing from source is impossible or explicitly requested.
- Do not infer that a launcher command is one-time; commands that start a
  process are repeat launch commands.
