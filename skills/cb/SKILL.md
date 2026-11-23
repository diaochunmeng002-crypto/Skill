---
name: cb
description: Resolve project breakpoint presets and manifest groups, then add, replace, or clear breakpoints in the currently running Visual Studio instance. Use when the user says "cb", "code breakpoint", asks to apply a breakpoint preset/manifest, create a breakpoint group, or synchronize manifest lines with Visual Studio. Do not use for startup delays or general program debugging.
metadata:
  short-description: Apply Visual Studio breakpoint manifests
---

# CB: Code Breakpoint

Manage Visual Studio breakpoints from small text manifests. A preset identifies
the repository, manifest directory, file-name format, and default section for
each numeric group.

## Safety Boundary

- Adding or replacing matching breakpoints is the normal operation.
- `-ClearAll` removes every breakpoint in the attached Visual Studio instance.
  Run it only when the user explicitly asks to clear all breakpoints.
- `-ClearOnly` performs the requested clear operation without adding new
  breakpoints.
- The scripts mutate an already-running Visual Studio instance through DTE;
  they do not launch Visual Studio.

## Inputs

Read [references/manifest.md](references/manifest.md) when creating or repairing
a manifest or preset. The generic preset template is
[presets/example.json](presets/example.json).

A manifest contains sections and `relative/path.ext:line` entries:

```text
[Default]
src/app/main.py:42
backend/server.py:100

[HTTP]
backend/server.py:158
```

Manifest line numbers must point to executable statements. Do not target a
`def`, `func`, or other declaration-only line when the debugger needs a body
breakpoint.

## Resolve the Request

1. Determine the source root and manifest directory from an explicit user path,
   a project preset, or the repository layout. Do not guess between unrelated
   checkouts when more than one candidate exists.
2. Determine the requested mode:
   - one manifest file;
   - one manifest group selected by numeric ID;
   - every manifest matching a filter;
   - preset defaults for any of the above.
3. If the user asks for new breakpoints, inspect the relevant source lines first
   and edit the manifest instead of hard-coding breakpoints into scripts.
4. Confirm that Visual Studio is running and that its DTE ProgID matches the
   preset. Visual Studio 2022 normally uses `VisualStudio.DTE.17.0`.

## Run the Workflow

Use the absolute path to `scripts/apply-breakpoints.ps1`.

Apply a preset:

```powershell
& "<skill-dir>\scripts\apply-breakpoints.ps1" -Preset project -GroupId 3.1
```

Apply one manifest:

```powershell
& "<skill-dir>\scripts\apply-breakpoints.ps1" `
  -SourceRoot "C:\repo" `
  -Manifest "debug\breakpoints\callstack-3.1.manifest" `
  -Set Default `
  -ClearMatching
```

Apply all manifests:

```powershell
& "<skill-dir>\scripts\apply-breakpoints.ps1" `
  -Preset project `
  -AllManifests `
  -ClearMatching
```

Clear only breakpoints represented by one manifest:

```powershell
& "<skill-dir>\scripts\apply-breakpoints.ps1" `
  -Preset project `
  -GroupId 3.1 `
  -ClearOnly
```

The command returns a summary containing added, existing, removed, missing-file,
and invalid-position counts. Report the actual summary instead of claiming
success from the command exit code alone.

To validate a manifest and its section selection without connecting to Visual
Studio, add `-ParseOnly`. This returns the resolved manifest, section names, and
deduplicated entries.

## Select a Manifest Group

The manifest filename is generated from `manifestNameFormat`, normally:

```text
callstack-{0}.manifest
```

The section defaults are resolved in this order:

1. Explicit `-Set`.
2. `sectionDefaultById[<GroupId>]`.
3. `sectionDefaultById["default"]`.
4. `Default`.

## Create or Repair Project Support

- Put reusable project settings in `presets/<project>.json`.
- Keep source paths relative to `sourceRoot`.
- Use `${PWD}` or normal environment-variable expansion only when a preset truly
  needs a discoverable checkout path.
- Keep breakpoint lists in source-controlled manifest files, not in the skill.
- Do not scan or modify tests unless the user explicitly requests it.

## Troubleshooting

- `Preset not found`: check the preset name and the skill's `presets` directory,
  or pass an absolute `-PresetPath`.
- `No sourceRoot`: fix `sourceRoot` or make at least one `discoverRoots` entry
  contain the configured manifest directory.
- `Could not connect to Visual Studio`: open the intended solution, use the
  matching 64-bit Developer PowerShell, and verify `-DteProgId`.
- `Manifest not found`: inspect the available files named by
  `manifestNameFormat`.
- `Invalid breakpoint position`: move the manifest entry to an executable line
  and rerun with `-ClearMatching`.
