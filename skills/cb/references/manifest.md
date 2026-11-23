# Breakpoint Manifest and Preset Format

## Manifest Format

Manifests are UTF-8 text files. Paths are relative to the preset `sourceRoot`.
Both `/` and `\` separators are accepted.

```text
# Optional comment

[Default]
src/app/main.py:42
backend/server.py:100

[HTTP]
backend/server.py:158
```

Rules:

- A section header uses `[SectionName]`.
- An entry uses `relative/path.ext:line`.
- Blank lines, `#` comments, and `;` comments are ignored.
- Entries before the first section are assigned to `Default`.
- The same normalized file and line is added only once.
- The line must be an executable statement. Declaration-only lines are often
  skipped or moved by Visual Studio.

## Preset Format

Presets live in `presets/<preset-name>.json`.

```json
{
  "id": "project",
  "sourceRoot": "${PWD}",
  "discoverRoots": [
    "C:\\src",
    "${PWD}"
  ],
  "manifestDir": "debug\\breakpoints",
  "manifestNameFormat": "callstack-{0}.manifest",
  "manifestFilter": "*.manifest",
  "relativePathAnchor": "",
  "dteProgId": "VisualStudio.DTE.17.0",
  "allManifestsSet": "Default",
  "sectionDefaultById": {
    "default": "Default",
    "1.1": "Quick",
    "3.1": "ProbeQuick"
  }
}
```

### Fields

| Field | Meaning |
|---|---|
| `id` | Human-readable preset identifier. |
| `sourceRoot` | Repository root; empty means discover from candidate roots. |
| `discoverRoots` | Ordered candidate roots used when `sourceRoot` is empty or invalid. |
| `manifestDir` | Manifest directory relative to `sourceRoot`, or an absolute path. |
| `manifestNameFormat` | `String.Format` template whose `{0}` is the group ID. |
| `manifestFilter` | File filter for all-manifest operations. |
| `relativePathAnchor` | Optional path fragment used to shorten breakpoint paths reported by DTE. |
| `dteProgId` | Visual Studio DTE ProgID, for example `VisualStudio.DTE.17.0`. |
| `allManifestsSet` | Default section for `-AllManifests`: `All`, `Default`, or one named section. |
| `sectionDefaultById` | Per-group default section, with `default` as the fallback. |

Token expansion supports:

- `${PWD}`: current PowerShell working directory.
- `%NAME%`: normal Windows environment-variable syntax.

Prefer a source-relative setup. Absolute checkout paths make presets hard to
share.

## Script Responsibilities

- `Get-CbPreset.ps1`: reads a preset, expands paths, discovers `sourceRoot`, and
  resolves `manifestDir`.
- `apply-breakpoints.ps1`: command router for preset, group, manifest, and
  all-manifest modes.
- `Set-Manifest-Group.ps1`: resolves one group's manifest and default section.
- `Set-All-Manifests.ps1`: applies one section to every matching manifest.
- `Set-VsBreakpoints.ps1`: parses, filters, deduplicates, and synchronizes the
  manifest with the active Visual Studio debugger.

## Clear Semantics

- `-ClearMatching`: before adding, remove breakpoints whose normalized source
  file belongs to the selected manifest. `-ClearWatching` is an alias for
  compatibility with older invocations.
- `-ClearAll`: remove every breakpoint in the active Visual Studio instance.
- `-ClearOnly`: perform the selected clear operation and do not add breakpoints.
- `-ParseOnly`: validate and return the selected manifest entries without
  connecting to Visual Studio.
- Without a clear switch, existing breakpoints remain and duplicate entries are
  skipped.

## Agent Checklist

1. Inspect a representative source line before adding it to a manifest.
2. Keep sections small and semantic, such as `Default`, `HTTP`, `Queue`, or
   `Worker`.
3. Use `-ClearMatching` when replacing a group's breakpoint set.
4. Never use `-ClearAll` unless the user explicitly requested it.
5. Verify the returned summary and report failed or skipped entries.
