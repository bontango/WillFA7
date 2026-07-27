<#
.SYNOPSIS
  Builds every active variant, files the programming images under bin\ and appends
  a changelog entry.

.DESCRIPTION
  A release is: bump SW_SUB2 (or SW_SUB1) in rtl\common\version_pkg.vhd, run this,
  commit, tag. The version is read back out of the sources here rather than passed
  in, so a release can never be filed under a number the FPGA does not display.

  Naming follows what is already in bin\: willfa7_v<board><sub1><sub2>.jic, and
  WillFA7_v<...>.pof for Cyclone II, which is programmed from the .pof directly.

.PARAMETER Variants
  Which variants to release. Default: all active ones.

.PARAMETER Note
  One line describing the release. Goes into bin\changelog.txt above the per
  variant list. Without it the changelog is not touched.

.PARAMETER SkipBuild
  Use the .sof/.pof/.jic already sitting in output_files instead of compiling again.

.EXAMPLE
  .\release.ps1 -Note "monorepo build, no functional change against x.20"
#>
param(
    [string[]]$Variants,
    [string]  $Note,
    [switch]  $SkipBuild
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$VarRoot   = Join-Path $RepoRoot 'variants'
$BinRoot   = Join-Path $RepoRoot 'bin'
$enc       = New-Object System.Text.UTF8Encoding($false)

# --- version out of the sources, never out of a parameter --------------------
function Get-HexConst([string]$Path, [string]$Name) {
    $m = Select-String -Path $Path -Pattern ("constant\s+$Name\s*:.*?x`"([0-9A-Fa-f])`"") -List
    if (-not $m) { throw "$Name not found in $Path" }
    return $m.Matches[0].Groups[1].Value
}
$verPkg = Join-Path $RepoRoot 'rtl\common\version_pkg.vhd'
$sub1   = Get-HexConst $verPkg 'SW_SUB1'
$sub2   = Get-HexConst $verPkg 'SW_SUB2'

$folders = Get-ChildItem $VarRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'variant.psd1') }
if ($Variants) { $folders = $folders | Where-Object { $Variants -contains $_.Name } }
else { $folders = $folders | Where-Object { -not (Import-PowerShellDataFile (Join-Path $_.FullName 'variant.psd1')).Dormant } }
if (-not $folders) { throw "no matching variant below $VarRoot" }

if (-not $SkipBuild) {
    & (Join-Path $ScriptDir 'build.ps1') -Variants ($folders.Name)
    if ($LASTEXITCODE -ne 0) { throw 'build failed - nothing filed' }
}

$filed = @()
foreach ($dir in $folders) {
    $meta = Import-PowerShellDataFile (Join-Path $dir.FullName 'variant.psd1')
    $ver  = "$($meta.BoardId)$sub1$sub2"          # e.g. 321
    $dest = Join-Path $BinRoot $meta.BinFolder
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }

    if ($meta.ReleaseArtifact -eq 'pof') {
        $src = Join-Path $dir.FullName 'output_files\WillFA7.pof'
        $dst = Join-Path $dest "WillFA7_v$ver.pof"
    } else {
        $src = Join-Path $dir.FullName 'output_files\willfa7.jic'
        $dst = Join-Path $dest "willfa7_v$ver.jic"
    }

    if (-not (Test-Path $src)) { Write-Host ("  {0,-22} MISSING {1}" -f $meta.Name, $src) -ForegroundColor Red; continue }
    Copy-Item $src $dst -Force
    Write-Host ("  {0,-22} -> {1}" -f $meta.Name, ($dst.Substring($RepoRoot.Length + 1))) -ForegroundColor Green
    $filed += [pscustomobject]@{ Variant = $meta.Name; Version = "$($meta.BoardId).$sub1$sub2"; File = $dst.Substring($BinRoot.Length + 1) }
}

if ($Note) {
    $log = Join-Path $BinRoot 'changelog.txt'
    $txt = "-- v x.$sub1$sub2 $(Get-Date -Format 'MM.yyyy') $Note`r`n"
    foreach ($f in $filed) { $txt += "--        $($f.Version)  $($f.File)`r`n" }
    [System.IO.File]::AppendAllText($log, $txt, $enc)
    Write-Host "changelog.txt updated" -ForegroundColor Cyan
}

Write-Host ''
$filed | Format-Table -AutoSize
