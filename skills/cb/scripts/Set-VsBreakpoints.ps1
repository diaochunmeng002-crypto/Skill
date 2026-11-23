[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Manifest,

    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [string]$Set = "All",
    [string]$RelativePathAnchor = "",
    [string]$DteProgId = "VisualStudio.DTE.17.0",
    [Alias("ClearWatching")]
    [switch]$ClearMatching,
    [switch]$ClearAll,
    [switch]$ClearOnly,
    [switch]$ParseOnly
)

$ErrorActionPreference = "Stop"

function Get-NormalizedFullPath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    try {
        return [IO.Path]::GetFullPath($Path).TrimEnd("\", "/").ToLowerInvariant()
    }
    catch {
        return $Path.Replace("/", "\").TrimEnd("\").ToLowerInvariant()
    }
}

function Get-SourceRelativePath {
    param(
        [string]$Path,
        [string]$Root,
        [string]$Anchor
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    $full = Get-NormalizedFullPath $Path
    $rootNorm = Get-NormalizedFullPath $Root
    if ($full.StartsWith($rootNorm + "\", [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($rootNorm.Length).TrimStart("\", "/").Replace("/", "\")
    }

    if ($Anchor) {
        $needle = $Anchor.Replace("/", "\").Trim("\").ToLowerInvariant()
        $index = $full.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase)
        if ($index -ge 0) {
            return $full.Substring($index)
        }
    }

    return $full
}

function Get-BreakpointKey {
    param(
        [string]$Path,
        [object]$LineNumber,
        [string]$Root,
        [string]$Anchor
    )

    $relative = Get-SourceRelativePath -Path $Path -Root $Root -Anchor $Anchor
    if (-not $relative) {
        return ""
    }

    return "{0}:{1}" -f $relative.ToLowerInvariant(), [string]$LineNumber
}

function Read-ManifestBreakpointItems {
    param(
        [string]$ManifestPath,
        [string]$Root
    )

    $sections = [ordered]@{}
    $items = @()
    $currentSection = "Default"
    $sections[$currentSection] = @()

    foreach ($rawLine in Get-Content -LiteralPath $ManifestPath -Encoding UTF8) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#") -or $line.StartsWith(";")) {
            continue
        }

        if ($line -match "^\[([^\]]+)\]$") {
            $currentSection = $Matches[1].Trim()
            if (-not $sections.Contains($currentSection)) {
                $sections[$currentSection] = @()
            }
            continue
        }

        if ($line -notmatch "^(.+):(\d+)\s*$") {
            Write-Warning "Skipping invalid manifest line: $line"
            continue
        }

        $relativePath = $Matches[1].Trim().Replace("/", "\").TrimStart(".\")
        $lineNumber = [int]$Matches[2]
        $fullPath = if ([IO.Path]::IsPathRooted($relativePath)) {
            [IO.Path]::GetFullPath($relativePath)
        }
        else {
            [IO.Path]::GetFullPath((Join-Path $Root $relativePath))
        }

        $item = [pscustomobject]@{
            PSTypeName   = "Cb.ManifestItem"
            Section      = $currentSection
            RelativePath = $relativePath
            FullPath     = $fullPath
            Line         = $lineNumber
        }
        $items += $item
        $sections[$currentSection] = @($sections[$currentSection]) + $item
    }

    return @{
        Path     = $ManifestPath
        Sections = $sections
        Items    = $items
    }
}

function Get-DedupedBreakpointItems {
    param(
        [object[]]$Items,
        [string]$Root,
        [string]$Anchor
    )

    $seen = @{}
    foreach ($item in $Items) {
        $key = Get-BreakpointKey -Path $item.FullPath -LineNumber $item.Line -Root $Root -Anchor $Anchor
        if (-not $key -or $seen.ContainsKey($key)) {
            continue
        }
        $seen[$key] = $true
        $item
    }
}

function Remove-AllDebuggerBreakpoints {
    param([object]$Dte)

    $removed = 0
    $snapshot = @($Dte.Debugger.Breakpoints)
    foreach ($breakpoint in $snapshot) {
        try {
            $breakpoint.Delete()
            $removed++
        }
        catch {
            # Breakpoints can disappear while Visual Studio is changing state.
        }
    }
    return $removed
}

$resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$resolvedManifest = if ([IO.Path]::IsPathRooted($Manifest)) {
    [IO.Path]::GetFullPath($Manifest)
}
else {
    [IO.Path]::GetFullPath((Join-Path $resolvedSourceRoot $Manifest))
}

if (-not (Test-Path -LiteralPath $resolvedManifest -PathType Leaf)) {
    throw "Manifest not found: $resolvedManifest"
}

$manifestData = Read-ManifestBreakpointItems -ManifestPath $resolvedManifest -Root $resolvedSourceRoot
$sectionNames = @($manifestData.Sections.Keys)
$requestedSet = if ([string]::IsNullOrWhiteSpace($Set)) { "All" } else { $Set.Trim() }

if ($requestedSet -eq "All") {
    $selectedItems = @($manifestData.Items)
}
else {
    $matchedSection = $sectionNames | Where-Object { $_ -ieq $requestedSet } | Select-Object -First 1
    if ($null -eq $matchedSection) {
        throw "Section '$requestedSet' not found in '$resolvedManifest'. Available: $($sectionNames -join ', ')"
    }
    $selectedItems = @($manifestData.Sections[$matchedSection])
}

$deduped = @(Get-DedupedBreakpointItems -Items $selectedItems -Root $resolvedSourceRoot -Anchor $RelativePathAnchor)
if ($deduped.Count -eq 0) {
    throw "No breakpoint entries selected from '$resolvedManifest' for Set '$requestedSet'."
}

if ($ParseOnly) {
    return [pscustomobject]@{
        PSTypeName = "Cb.ParseResult"
        Manifest   = $resolvedManifest
        Set        = $requestedSet
        Sections   = $sectionNames
        Entries    = $deduped
    }
}

try {
    $dte = [Runtime.InteropServices.Marshal]::GetActiveObject($DteProgId)
}
catch {
    throw "Could not connect to Visual Studio '$DteProgId'. Open the solution and run this command from a matching 64-bit Developer PowerShell. $($_.Exception.Message)"
}

if ($ClearOnly -and -not $ClearAll) {
    $ClearMatching = $true
}

$removed = 0
if ($ClearAll) {
    $removed = Remove-AllDebuggerBreakpoints -Dte $dte
}
elseif ($ClearMatching) {
    $manifestFiles = @{}
    foreach ($item in $manifestData.Items) {
        $manifestFiles[(Get-NormalizedFullPath $item.FullPath)] = $true
    }

    $snapshot = @($dte.Debugger.Breakpoints)
    foreach ($breakpoint in $snapshot) {
        $fullPath = Get-NormalizedFullPath ([string]$breakpoint.FileName)
        if ($manifestFiles.ContainsKey($fullPath)) {
            try {
                $breakpoint.Delete()
                $removed++
            }
            catch {
                # Continue with the remaining breakpoints and report the totals.
            }
        }
    }
}

if ($ClearOnly) {
    return [pscustomobject]@{
        PSTypeName   = "Cb.Result"
        Manifest     = $resolvedManifest
        Set          = $requestedSet
        Added        = 0
        Existing     = 0
        Removed      = $removed
        MissingFiles = 0
        Invalid      = 0
        ClearMode    = if ($ClearAll) { "All" } else { "Matching" }
    }
}

$existingKeys = @{}
foreach ($breakpoint in $dte.Debugger.Breakpoints) {
    $key = Get-BreakpointKey `
        -Path ([string]$breakpoint.FileName) `
        -LineNumber ([int]$breakpoint.FileLine) `
        -Root $resolvedSourceRoot `
        -Anchor $RelativePathAnchor
    if ($key) {
        $existingKeys[$key] = $true
    }
}

$added = 0
$existing = 0
$missingFiles = 0
$invalid = 0

foreach ($item in $deduped) {
    if (-not (Test-Path -LiteralPath $item.FullPath -PathType Leaf)) {
        Write-Warning "Skipping missing source file: $($item.RelativePath)"
        $missingFiles++
        continue
    }

    $key = Get-BreakpointKey -Path $item.FullPath -LineNumber $item.Line -Root $resolvedSourceRoot -Anchor $RelativePathAnchor
    if ($existingKeys.ContainsKey($key)) {
        $existing++
        continue
    }

    try {
        [void]$dte.Debugger.Breakpoints.Add($item.FullPath, [int]$item.Line, 1)
        $existingKeys[$key] = $true
        $added++
    }
    catch {
        Write-Warning "Invalid breakpoint position $($item.RelativePath):$($item.Line): $($_.Exception.Message)"
        $invalid++
    }
}

[pscustomobject]@{
    PSTypeName   = "Cb.Result"
    Manifest     = $resolvedManifest
    Set          = $requestedSet
    Added        = $added
    Existing     = $existing
    Removed      = $removed
    MissingFiles = $missingFiles
    Invalid      = $invalid
    ClearMode    = if ($ClearAll) { "All" } elseif ($ClearMatching) { "Matching" } else { "None" }
}
