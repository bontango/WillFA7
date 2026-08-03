<#
.SYNOPSIS
  Generates variants\<name>\WillFA7.qsf from the shared parts plus the per-board parts.

.DESCRIPTION
  The .qsf used to be hand maintained per variant, which is how a new .vhd ended up
  missing from six out of seven of them. It is now assembled from:

    scripts\common_header.tcl   global assignments identical in every variant
    variants\<n>\device.tcl     FAMILY, DEVICE and whatever else is board specific
    variants\<n>\pins.tcl       the set_location_assignment lines
    scripts\files_common.tcl    sources every variant needs, incl. top/WillFA7.vhd
    scripts\files_<family>.tcl  the megafunctions, chosen via RtlFamily
    scripts\files_<option>.tcl  one per entry in Options ('serial_api', 'sound')

  RtlFamily, Options and VirtualPins come from variants\<n>\variant.psd1.

  Optional top level ports that a board does not have get VIRTUAL_PIN. That is not
  cosmetic: a declared output port without a location is a *used* pin to Quartus,
  RESERVE_ALL_UNUSED_PINS does not cover it, and it would be placed and driven on
  a real pin of the board.

.PARAMETER Variants
  Which variants to generate. Default: all folders below variants\ that have a variant.psd1.

.PARAMETER Check
  Do not write. Compare the generated content against the .qsf on disk and report
  the difference. Exit code 1 if anything differs.

.EXAMPLE
  .\gen_qsf.ps1

.EXAMPLE
  .\gen_qsf.ps1 -Check
#>
param(
    [string[]]$Variants,
    [switch]  $Check
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$VarRoot   = Join-Path $RepoRoot 'variants'
$enc       = New-Object System.Text.UTF8Encoding($false)

function Read-Fragment([string]$Path) {
    if (-not (Test-Path $Path)) { throw "missing fragment: $Path" }
    # Drop the fragment's own header comment - the generated file gets its own.
    return @(Get-Content $Path | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' })
}

$folders = Get-ChildItem $VarRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'variant.psd1') }
if ($Variants) { $folders = $folders | Where-Object { $Variants -contains $_.Name } }
# The dormant sound variants carry their own top level and their own frozen copies of
# the common modules, so they do not fit this model. Their .qsf stays hand maintained
# and is marked Generated = $false. Never overwrite it from here.
$folders = $folders | Where-Object {
    $meta = Import-PowerShellDataFile (Join-Path $_.FullName 'variant.psd1')
    -not ($meta.ContainsKey('Generated') -and -not $meta.Generated)
}
if (-not $folders) { throw "no generated variants found below $VarRoot" }

$common = Read-Fragment (Join-Path $ScriptDir 'common_header.tcl')
$fail   = $false

foreach ($dir in $folders) {
    $meta = Import-PowerShellDataFile (Join-Path $dir.FullName 'variant.psd1')

    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('# ---------------------------------------------------------------------------')
    $out.Add('# GENERATED FILE - do not edit.')
    $out.Add('#')
    $out.Add("# Variant : $($meta.Name) - $($meta.Title)")
    $out.Add('# Made by : scripts\gen_qsf.ps1')
    $out.Add('# Sources : scripts\common_header.tcl, device.tcl, pins.tcl,')
    $out.Add('#           scripts\files_common.tcl + files_<family>.tcl + files_<option>.tcl')
    $out.Add('#')
    $out.Add('# Change device.tcl / pins.tcl / variant.psd1 or the file lists, then rerun')
    $out.Add('# gen_qsf.ps1. Editing this file directly is lost on the next run.')
    $out.Add('# ---------------------------------------------------------------------------')
    $out.Add('')
    $out.Add('# --- board -----------------------------------------------------------------')
    # Which entity is the top level. Only cyclone_ii differs: Quartus 13.0sp1 Web
    # Edition ignores VIRTUAL_PIN, so that board uses the shell top/WillFA7_cii.vhd,
    # which does not declare the optional ports at all. See that file for the details.
    $topEntity = 'WillFA7'
    if ($meta.TopEntity) { $topEntity = $meta.TopEntity }
    $out.Add("set_global_assignment -name TOP_LEVEL_ENTITY $topEntity")
    Read-Fragment (Join-Path $dir.FullName 'device.tcl') | ForEach-Object { $out.Add($_) }
    $out.Add('')
    $out.Add('# --- shared globals --------------------------------------------------------')
    $common | ForEach-Object { $out.Add($_) }

    if ($meta.VirtualPins -and $meta.VirtualPins.Count -gt 0) {
        $out.Add('')
        $out.Add('# --- optional top level ports this board does not have ---------------------')
        $out.Add('# They stay in the port list so all variants share one top level. VIRTUAL_PIN')
        $out.Add('# keeps Quartus from placing and driving them on a real pin.')
        foreach ($p in $meta.VirtualPins) {
            $out.Add("set_instance_assignment -name VIRTUAL_PIN ON -to $p")
        }
    }

    $out.Add('')
    $out.Add('# --- pins ------------------------------------------------------------------')
    Read-Fragment (Join-Path $dir.FullName 'pins.tcl') | ForEach-Object { $out.Add($_) }

    $out.Add('')
    $out.Add('# --- sources ---------------------------------------------------------------')
    Read-Fragment (Join-Path $ScriptDir 'files_common.tcl') | ForEach-Object { $out.Add($_) }
    Read-Fragment (Join-Path $ScriptDir "files_$($meta.RtlFamily).tcl") | ForEach-Object { $out.Add($_) }
    foreach ($opt in @($meta.Options)) {
        if (-not $opt) { continue }
        Read-Fragment (Join-Path $ScriptDir "files_$opt.tcl") | ForEach-Object { $out.Add($_) }
    }

    $text = ($out -join "`r`n") + "`r`n"
    $qsf  = Join-Path $dir.FullName 'WillFA7.qsf'

    if ($Check) {
        $have = if (Test-Path $qsf) { [System.IO.File]::ReadAllText($qsf) } else { '' }
        if ($have -eq $text) {
            Write-Host ("  {0,-22} up to date" -f $meta.Name) -ForegroundColor Green
        } else {
            Write-Host ("  {0,-22} DIFFERS" -f $meta.Name) -ForegroundColor Red
            $fail = $true
            $d = Compare-Object ($have -split "`r`n") ($text -split "`r`n")
            $d | ForEach-Object { Write-Host ("      {0} {1}" -f $_.SideIndicator, $_.InputObject) }
        }
    } else {
        [System.IO.File]::WriteAllText($qsf, $text, $enc)
        Write-Host ("  {0,-22} written ({1} lines)" -f $meta.Name, $out.Count) -ForegroundColor Green
    }
}

if ($fail) { exit 1 }
