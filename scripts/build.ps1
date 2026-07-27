<#
.SYNOPSIS
  Full Quartus compile of one or more WillFA7 variants, including the programming file.

.DESCRIPTION
  Runs quartus_sh --flow compile, which produces output_files\WillFA7.sof and .pof,
  then quartus_cpf on the variant's willfa7.cof to get the .jic for the serial
  configuration device.

  Cyclone II is the exception: that board is programmed from the .pof straight out
  of the compile (EPCS4), so no .jic is made. That is recorded as ReleaseArtifact
  in variants\cyclone_ii\variant.psd1.

  For a quick syntax or resource check use check.ps1 instead - it is much faster.

.PARAMETER Variants
  Variant folder names. Default: all active ones.

.PARAMETER All
  Include the variants marked dormant. They are known not to build.

.EXAMPLE
  .\build.ps1 cyclone_iv_v4

.EXAMPLE
  .\build.ps1
#>
param(
    [Parameter(Position = 0)]
    [string[]]$Variants,
    [switch]  $All
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$VarRoot   = Join-Path $RepoRoot 'variants'

$QuartusBin = [ordered]@{
    'Cyclone II' = 'C:\altera\13.0sp1\quartus\bin64'
    'DEFAULT'    = 'C:\intelFPGA_lite\22.1std\quartus\bin64'
}
function Get-QuartusBin([string]$Family) {
    foreach ($key in $QuartusBin.Keys) {
        if ($key -eq 'DEFAULT') { continue }
        if ($Family -like "*$key*") { return $QuartusBin[$key] }
    }
    return $QuartusBin['DEFAULT']
}

$folders = Get-ChildItem $VarRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'variant.psd1') }
if ($Variants)  { $folders = $folders | Where-Object { $Variants -contains $_.Name } }
elseif (-not $All) {
    $folders = $folders | Where-Object { -not (Import-PowerShellDataFile (Join-Path $_.FullName 'variant.psd1')).Dormant }
}
if (-not $folders) { throw "no matching variant below $VarRoot" }

$results = @()
foreach ($dir in $folders) {
    $meta   = Import-PowerShellDataFile (Join-Path $dir.FullName 'variant.psd1')
    $qsf    = Join-Path $dir.FullName 'WillFA7.qsf'
    $family = ''
    $fLine  = Select-String -Path $qsf -Pattern '-name FAMILY\s+"?([^"\r\n]+)"?' -List
    if ($fLine) { $family = $fLine.Matches[0].Groups[1].Value.Trim().Trim('"') }
    $bin = Get-QuartusBin $family

    Write-Host ("  {0,-22} {1}" -f $dir.Name, $family) -ForegroundColor Cyan
    $status = 'ok'; $artifacts = @()

    Push-Location $dir.FullName
    try {
        $out = & (Join-Path $bin 'quartus_sh.exe') --flow compile WillFA7
        if ($LASTEXITCODE -ne 0) {
            $status = 'compile FAILED'
            $err = $out | Select-String -Pattern '^Error \(' | Select-Object -First 1
            if ($err) { Write-Host "       $($err.Line.Trim())" -ForegroundColor Red }
        }
        else {
            foreach ($f in 'output_files\WillFA7.sof','output_files\WillFA7.pof') {
                if (Test-Path $f) { $artifacts += (Split-Path $f -Leaf) }
            }
            # .jic only where the board boots from a serial configuration device
            # that is not written directly by the compile.
            $wantJic = ($meta.ReleaseArtifact -ne 'pof')
            if ($wantJic -and (Test-Path 'willfa7.cof')) {
                $null = & (Join-Path $bin 'quartus_cpf.exe') -c 'willfa7.cof'
                if ($LASTEXITCODE -ne 0) { $status = 'cpf FAILED' }
                elseif (Test-Path 'output_files\willfa7.jic') { $artifacts += 'willfa7.jic' }
            }
        }
    }
    finally { Pop-Location }

    if ($status -eq 'ok') { Write-Host ("       -> ok: {0}" -f ($artifacts -join ', ')) -ForegroundColor Green }
    else                  { Write-Host "       -> $status" -ForegroundColor Red }

    $results += [pscustomobject]@{ Variant = $dir.Name; Status = $status; Artifacts = ($artifacts -join ', ') }
}

Write-Host ''
$results | Format-Table -AutoSize
if ($results | Where-Object { $_.Status -ne 'ok' }) { exit 1 }
