[CmdletBinding()]
param(
    [string]$Preset = "",
    [string]$PresetPath = "",
    [string]$SourceRoot = "",
    [string]$ManifestDir = "",
    [string]$Manifest = "",

    [Alias("Id")]
    [string]$GroupId = "",

    [string]$Set = "",
    [switch]$AllManifests,
    [Alias("ClearWatching")]
    [switch]$ClearMatching,
    [switch]$ClearAll,
    [switch]$ClearAllStudy,
    [switch]$ClearOnly,
    [switch]$ParseOnly,

    [string]$ManifestNameFormat = "",
    [string]$ManifestFilter = "",
    [string]$RelativePathAnchor = "",
    [string]$DteProgId = "",
    [hashtable]$SectionDefaultById = $null
)

$ErrorActionPreference = "Stop"

if ($ClearAllStudy) {
    $ClearAll = $true
}

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "Set-VsBreakpoints.ps1") -PathType Leaf)) {
    throw "Required script missing: $(Join-Path $PSScriptRoot 'Set-VsBreakpoints.ps1')"
}

$presetData = $null
if ($Preset -or $PresetPath) {
    $presetArgs = @{ PresetName = $Preset }
    if ($PresetPath) {
        $presetArgs.PresetPath = $PresetPath
    }
    $presetData = & (Join-Path $PSScriptRoot "Get-CbPreset.ps1") @presetArgs

    if (-not $PSBoundParameters.ContainsKey("SourceRoot") -or -not $SourceRoot) {
        $SourceRoot = $presetData.SourceRoot
    }
    if (-not $PSBoundParameters.ContainsKey("ManifestDir") -or -not $ManifestDir) {
        $ManifestDir = $presetData.ManifestDir
    }
    if (-not $PSBoundParameters.ContainsKey("ManifestNameFormat") -or -not $ManifestNameFormat) {
        $ManifestNameFormat = $presetData.ManifestNameFormat
    }
    if (-not $PSBoundParameters.ContainsKey("ManifestFilter") -or -not $ManifestFilter) {
        $ManifestFilter = $presetData.ManifestFilter
    }
    if (-not $PSBoundParameters.ContainsKey("RelativePathAnchor")) {
        $RelativePathAnchor = $presetData.RelativePathAnchor
    }
    if (-not $PSBoundParameters.ContainsKey("DteProgId") -or -not $DteProgId) {
        $DteProgId = $presetData.DteProgId
    }
    if ($null -eq $SectionDefaultById) {
        $SectionDefaultById = $presetData.SectionDefaultById
    }
}

if (-not $SourceRoot) {
    throw "Pass -Preset, -PresetPath, or -SourceRoot."
}
$resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path

if (-not $DteProgId) {
    $DteProgId = "VisualStudio.DTE.17.0"
}
if (-not $ManifestNameFormat) {
    $ManifestNameFormat = "callstack-{0}.manifest"
}
if (-not $ManifestFilter) {
    $ManifestFilter = "*.manifest"
}
if ($null -eq $SectionDefaultById) {
    $SectionDefaultById = @{ default = "Default" }
}

if ($Manifest) {
    $requestedSet = if ($Set) { $Set } else { "All" }
    return & (Join-Path $PSScriptRoot "Set-VsBreakpoints.ps1") `
        -Manifest $Manifest `
        -SourceRoot $resolvedSourceRoot `
        -Set $requestedSet `
        -RelativePathAnchor $RelativePathAnchor `
        -DteProgId $DteProgId `
        -ClearMatching:$ClearMatching `
        -ClearAll:$ClearAll `
        -ClearOnly:$ClearOnly `
        -ParseOnly:$ParseOnly
}

if (-not $ManifestDir) {
    throw "Pass -Manifest, -AllManifests, or -ManifestDir with -GroupId."
}

if ($AllManifests) {
    $requestedSet = if ($Set) {
        $Set
    }
    elseif ($presetData -and $presetData.AllManifestsSet) {
        $presetData.AllManifestsSet
    }
    else {
        "Default"
    }

    return & (Join-Path $PSScriptRoot "Set-All-Manifests.ps1") `
        -ManifestDir $ManifestDir `
        -SourceRoot $resolvedSourceRoot `
        -Filter $ManifestFilter `
        -Set $requestedSet `
        -RelativePathAnchor $RelativePathAnchor `
        -DteProgId $DteProgId `
        -ClearMatching:$ClearMatching `
        -ClearAll:$ClearAll `
        -ClearOnly:$ClearOnly `
        -ParseOnly:$ParseOnly
}

if (-not $GroupId) {
    throw "Pass -GroupId, -Manifest, or -AllManifests."
}

$groupArgs = @{
    ManifestDir         = $ManifestDir
    SourceRoot          = $resolvedSourceRoot
    GroupId             = $GroupId
    Set                 = $Set
    ManifestNameFormat  = $ManifestNameFormat
    RelativePathAnchor  = $RelativePathAnchor
    DteProgId           = $DteProgId
    SectionDefaultById  = $SectionDefaultById
    ClearMatching       = $ClearMatching
    ClearAll            = $ClearAll
    ClearOnly           = $ClearOnly
    ParseOnly           = $ParseOnly
}

& (Join-Path $PSScriptRoot "Set-Manifest-Group.ps1") @groupArgs
