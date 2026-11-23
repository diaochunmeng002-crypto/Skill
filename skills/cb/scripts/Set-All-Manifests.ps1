[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestDir,

    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [string]$Filter = "*.manifest",
    [string]$Set = "Default",
    [string]$RelativePathAnchor = "",
    [string]$DteProgId = "VisualStudio.DTE.17.0",
    [Alias("ClearWatching")]
    [switch]$ClearMatching,
    [switch]$ClearAll,
    [switch]$ClearOnly,
    [switch]$ParseOnly
)

$ErrorActionPreference = "Stop"

$resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$resolvedManifestDir = if ([IO.Path]::IsPathRooted($ManifestDir)) {
    [IO.Path]::GetFullPath($ManifestDir)
}
else {
    [IO.Path]::GetFullPath((Join-Path $resolvedSourceRoot $ManifestDir))
}

if (-not (Test-Path -LiteralPath $resolvedManifestDir -PathType Container)) {
    throw "Manifest directory not found: $resolvedManifestDir"
}

$manifests = @(Get-ChildItem -LiteralPath $resolvedManifestDir -File -Filter $Filter | Sort-Object Name)
if ($manifests.Count -eq 0) {
    throw "No manifests matched '$Filter' in $resolvedManifestDir"
}

$results = foreach ($manifest in $manifests) {
    $clearAllThisManifest = $ClearAll -and $manifest -eq $manifests[0]
    & (Join-Path $PSScriptRoot "Set-VsBreakpoints.ps1") `
        -Manifest $manifest.FullName `
        -SourceRoot $resolvedSourceRoot `
        -Set $Set `
        -RelativePathAnchor $RelativePathAnchor `
        -DteProgId $DteProgId `
        -ClearMatching:$ClearMatching `
        -ClearAll:$clearAllThisManifest `
        -ClearOnly:$ClearOnly `
        -ParseOnly:$ParseOnly
}

$results
