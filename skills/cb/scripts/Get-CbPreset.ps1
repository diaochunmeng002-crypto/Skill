[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$PresetName = "",

    [string]$PresetPath = "",

    [string]$PresetRoot = (Join-Path $PSScriptRoot "..\presets")
)

$ErrorActionPreference = "Stop"

function Expand-CbToken {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $expanded = $Text.Replace("`${PWD}", (Get-Location).ProviderPath)
    return [Environment]::ExpandEnvironmentVariables($expanded)
}

function Test-SourceRootCandidate {
    param(
        [string]$Root,
        [string]$ManifestRelative
    )

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root -PathType Container)) {
        return $false
    }

    $manifestPath = if ([IO.Path]::IsPathRooted($ManifestRelative)) {
        $ManifestRelative
    }
    else {
        Join-Path (Resolve-Path -LiteralPath $Root).Path $ManifestRelative
    }

    return Test-Path -LiteralPath $manifestPath -PathType Container
}

if ([string]::IsNullOrWhiteSpace($PresetPath)) {
    if ([string]::IsNullOrWhiteSpace($PresetName)) {
        throw "Pass -PresetName or -PresetPath."
    }

    $presetFile = if ([IO.Path]::IsPathRooted($PresetName)) {
        $PresetName
    }
    else {
        $leaf = if ([IO.Path]::GetExtension($PresetName) -eq ".json") {
            $PresetName
        }
        else {
            "$PresetName.json"
        }
        Join-Path $PresetRoot $leaf
    }
}
else {
    $presetFile = $PresetPath
}

$presetFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($presetFile)
if (-not (Test-Path -LiteralPath $presetFile -PathType Leaf)) {
    throw "Preset not found: $presetFile"
}

try {
    $raw = Get-Content -LiteralPath $presetFile -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    throw "Could not parse preset '$presetFile': $($_.Exception.Message)"
}

$manifestRelative = if ([string]::IsNullOrWhiteSpace([string]$raw.manifestDir)) {
    "."
}
else {
    Expand-CbToken ([string]$raw.manifestDir)
}

$sourceRoot = Expand-CbToken ([string]$raw.sourceRoot)
if ($sourceRoot -and -not (Test-SourceRootCandidate -Root $sourceRoot -ManifestRelative $manifestRelative)) {
    $sourceRoot = ""
}

if (-not $sourceRoot) {
    foreach ($candidate in @($raw.discoverRoots)) {
        $expandedCandidate = Expand-CbToken ([string]$candidate)
        if (Test-SourceRootCandidate -Root $expandedCandidate -ManifestRelative $manifestRelative) {
            $sourceRoot = (Resolve-Path -LiteralPath $expandedCandidate).Path
            break
        }
    }
}

if (-not $sourceRoot) {
    throw "Preset '$presetFile' has no sourceRoot, and no discoverRoots entry contains manifestDir '$manifestRelative'."
}

$resolvedManifestDir = if ([IO.Path]::IsPathRooted($manifestRelative)) {
    [IO.Path]::GetFullPath($manifestRelative)
}
else {
    [IO.Path]::GetFullPath((Join-Path $sourceRoot $manifestRelative))
}

if (-not (Test-Path -LiteralPath $resolvedManifestDir -PathType Container)) {
    throw "Resolved manifestDir is not a directory: $resolvedManifestDir"
}

$sectionMap = @{}
if ($null -ne $raw.sectionDefaultById) {
    foreach ($property in $raw.sectionDefaultById.PSObject.Properties) {
        $sectionMap[$property.Name] = [string]$property.Value
    }
}
if (-not $sectionMap.ContainsKey("default")) {
    $sectionMap["default"] = "Default"
}

[pscustomobject]@{
    PSTypeName          = "Cb.Preset"
    Name                = if ($raw.id) { [string]$raw.id } else { [IO.Path]::GetFileNameWithoutExtension($presetFile) }
    PresetPath          = $presetFile
    SourceRoot          = $sourceRoot
    ManifestDir         = $resolvedManifestDir
    ManifestNameFormat  = if ($raw.manifestNameFormat) { [string]$raw.manifestNameFormat } else { "callstack-{0}.manifest" }
    ManifestFilter      = if ($raw.manifestFilter) { [string]$raw.manifestFilter } else { "*.manifest" }
    RelativePathAnchor  = if ($raw.relativePathAnchor) { Expand-CbToken ([string]$raw.relativePathAnchor) } else { "" }
    DteProgId           = if ($raw.dteProgId) { [string]$raw.dteProgId } else { "VisualStudio.DTE.17.0" }
    AllManifestsSet     = if ($raw.allManifestsSet) { [string]$raw.allManifestsSet } else { "Default" }
    SectionDefaultById  = $sectionMap
}
