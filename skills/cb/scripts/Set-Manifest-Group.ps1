[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestDir,

    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [Alias("Id", "Group")]
    [string]$GroupId,

    [string]$Set = "",
    [string]$ManifestNameFormat = "callstack-{0}.manifest",
    [string]$RelativePathAnchor = "",
    [string]$DteProgId = "VisualStudio.DTE.17.0",
    [hashtable]$SectionDefaultById = @{},
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

try {
    $manifestName = $ManifestNameFormat -f $GroupId
}
catch {
    throw "Invalid ManifestNameFormat '$ManifestNameFormat': $($_.Exception.Message)"
}
$manifestPath = Join-Path $resolvedManifestDir $manifestName

if ([string]::IsNullOrWhiteSpace($Set)) {
    if ($SectionDefaultById.ContainsKey($GroupId)) {
        $Set = [string]$SectionDefaultById[$GroupId]
    }
    elseif ($SectionDefaultById.ContainsKey("default")) {
        $Set = [string]$SectionDefaultById["default"]
    }
    else {
        $Set = "Default"
    }
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    $prefix = ""
    $suffix = ""
    if ($ManifestNameFormat -match "^(.*)\{0[^}]*\}(.*)$") {
        $prefix = $Matches[1]
        $suffix = $Matches[2]
    }

    $available = Get-ChildItem -LiteralPath $resolvedManifestDir -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and
            $_.Name.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase)
        } |
        ForEach-Object {
            $start = [Math]::Min($prefix.Length, $_.Name.Length)
            $length = [Math]::Max(0, $_.Name.Length - $prefix.Length - $suffix.Length)
            $_.Name.Substring($start, $length)
        } |
        Sort-Object -Unique

    $hint = if ($available) { " Available group IDs: $($available -join ', ')" } else { "" }
    throw "Manifest not found for GroupId '$GroupId': $manifestPath.$hint"
}

& (Join-Path $PSScriptRoot "Set-VsBreakpoints.ps1") `
    -Manifest $manifestPath `
    -SourceRoot $resolvedSourceRoot `
    -Set $Set `
    -RelativePathAnchor $RelativePathAnchor `
    -DteProgId $DteProgId `
    -ClearMatching:$ClearMatching `
    -ClearAll:$ClearAll `
    -ClearOnly:$ClearOnly `
    -ParseOnly:$ParseOnly
