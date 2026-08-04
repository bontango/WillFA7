<#
.SYNOPSIS
  Builds the WillFA7 variants and compares result, resources and timing in one table.

.DESCRIPTION
  Scans variants\ for subfolders containing a *.qpf, picks the Quartus installation
  that matches the FAMILY line of the *.qsf and runs Analysis & Synthesis, optionally
  the Fitter and the Timing Analyzer as well. Afterwards fit.rpt / map.rpt / sta.rpt
  are parsed and, unless -NoBaseline is given, checked against scripts\baseline.csv.

  Without a switch only quartus_map runs - fast, catches syntax and elaboration
  errors. Resource and timing figures need -Fit.

  Variants marked Dormant in their variant.psd1 are skipped by default. None is today,
  so this checks all six; use -All if a dormant one is added later.

.PARAMETER Root
  Folder holding the variant folders. Default: the variants\ folder next to this script.

.PARAMETER Variants
  Folder names to check. Default: all active ones.

.PARAMETER Fit
  Run the Fitter and the Timing Analyzer on top of the mapper (gives LE/Memory/Slack).

.PARAMETER Full
  Run the complete flow (map+fit+asm+sta), producing .sof/.pof.

.PARAMETER All
  Also check the variants marked Dormant in their variant.psd1. None is today.

.PARAMETER NoBaseline
  Do not compare against scripts\baseline.csv.

.PARAMETER NoGen
  Do not regenerate the .qsf first. Only for deliberately checking a hand edited
  one - the next run without the switch throws that edit away again.

.EXAMPLE
  .\check.ps1 -Fit

.EXAMPLE
  .\check.ps1 -Variants cyclone_ii -Fit
#>
param(
    [string]  $Root,
    [string[]]$Variants,
    [switch]  $Fit,
    [switch]  $Full,
    [switch]  $All,
    [switch]  $NoBaseline,
    [switch]  $NoGen
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$OwnRoot   = -not $Root                      # working on the repo's own variants\
if (-not $Root) { $Root = Join-Path $RepoRoot 'variants' }

# Quartus rewrites the .qsf by itself when the project has been open in the IDE -
# 08.2026 it appended a second PARTITION_HIERARCHY line to s_cyclone_iv_v4. The .qsf
# is a generated file, so regenerate it before anything reads it. Otherwise the
# numbers below describe a project nobody can reproduce from device.tcl / pins.tcl /
# variant.psd1. Silent unless something actually had to be put back.
if ($OwnRoot -and -not $NoGen) { & (Join-Path $ScriptDir 'gen_qsf.ps1') -Quiet }

# How much setup slack drift counts as a finding, and below which value the slack
# itself is worth flagging regardless of the baseline.
#
# Measured, not guessed: two runs of cyclone_10 over byte-identical sources produced
# 5.690 and 6.791 ns, so 1.1 ns of the number is placement noise. A tolerance below
# that only produces false alarms, and a column that cries wolf every run is a column
# nobody reads. The clock period is 20 ns, so 1.5 ns of slop costs nothing in safety -
# what actually matters is the absolute value, which SlackFloor covers.
$SlackTolerance = 1.5
$SlackFloor     = 1.0

# ---------------------------------------------------------------------------
# Quartus installations. Key = substring of the FAMILY value in the .qsf,
# DEFAULT applies when nothing matches. quartus_sh is not on the PATH here.
# ---------------------------------------------------------------------------
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

# First number out of lines like "; Total logic elements ; 4,368 / 4,608 ( 95 % ) ;"
function Get-ReportValue([string]$Path, [string]$Label) {
    if (-not (Test-Path $Path)) { return $null }
    $line = Select-String -Path $Path -Pattern ("^;\s+" + [regex]::Escape($Label) + "\s+;") -List
    if ($null -eq $line) { return $null }
    $parts = $line.Line -split ';'
    if ($parts.Count -lt 3) { return $null }
    return $parts[2].Trim()
}

# "4,368 / 4,608 ( 95 % )" -> 4368
function Get-FirstNumber([string]$Text) {
    if (-not $Text) { return $null }
    if ($Text -match '([\d,]+)') { return [int](($Matches[1]) -replace ',','') }
    return $null
}

# Worst setup slack over all clocks, from the Setup Summary.
# Careful: "... Model Setup Summary" also appears in the table of contents of the
# .rpt, and right behind the table other tables with completely different numbers
# follow. The table is therefore strictly delimited: it consists only of lines
# starting with ';' or '+', the first line without that pattern ends it.
function Get-WorstSlack([string]$StaPath) {
    if (-not (Test-Path $StaPath)) { return $null }
    $inTable = $false
    $worst   = $null
    foreach ($line in Get-Content $StaPath) {
        if (-not $inTable) {
            # Only real section headings, not the TOC line ("  12. Slow ...")
            if ($line -match 'Model Setup Summary' -and $line -notmatch '^\s*\d+\.\s') {
                $inTable = $true
            }
            continue
        }
        if ($line -notmatch '^\s*[;+]') { $inTable = $false; continue }
        # Data line "; <clock> ; <slack> ; <tns> ;" - the header line has text in
        # column 2 and therefore fails the number pattern.
        if ($line -match '^;\s+\S.*?;\s+(-?\d+(?:\.\d+)?)\s+;') {
            $val = [double]$Matches[1]
            if ($null -eq $worst -or $val -lt $worst) { $worst = $val }
        }
    }
    if ($null -eq $worst) { return $null }
    return $worst.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
}

# Warnings worth watching. 10036 = port declared but never used (R5101 clock_a),
# 10492/10540 = signal used but never assigned. Those three are expected in
# specific places; anything else in this class means something got lost.
function Get-WatchedWarnings([string]$RptPath) {
    if (-not (Test-Path $RptPath)) { return @() }
    $hits = Select-String -Path $RptPath -Pattern 'Warning \((10036|10492|10540)\)'
    if (-not $hits) { return @() }
    return @($hits | ForEach-Object { $_.Line.Trim() })
}

# "22.1std" / "13.0sp1" out of the installation path
function Get-QuartusLabel([string]$BinPath) {
    if ($BinPath -match '\\([^\\]+)\\quartus\\bin') { return $Matches[1] }
    return $BinPath
}

# ---------------------------------------------------------------------------

if (-not (Test-Path $Root)) { throw "Root not found: $Root" }

$found = Get-ChildItem -Path $Root -Directory | Where-Object {
    Get-ChildItem -Path $_.FullName -Filter '*.qpf' -File -ErrorAction SilentlyContinue
}
if ($Variants) {
    $found = $found | Where-Object { $Variants -contains $_.Name }
}
elseif (-not $All) {
    # Skip the dormant ones unless explicitly asked for.
    $found = $found | Where-Object {
        $meta = Join-Path $_.FullName 'variant.psd1'
        if (-not (Test-Path $meta)) { return $true }
        $data = Import-PowerShellDataFile $meta
        -not $data.Dormant
    }
}
if (-not $found) { throw "No variant folders with *.qpf below $Root" }

$baseline = @{}
$baselineFile = Join-Path $ScriptDir 'baseline.csv'
if (-not $NoBaseline -and (Test-Path $baselineFile)) {
    foreach ($row in (Import-Csv $baselineFile -Delimiter ';')) { $baseline[$row.Variant] = $row }
}

$mode = 'map'
if ($Fit)  { $mode = 'fit'  }
if ($Full) { $mode = 'full' }
Write-Host "Mode: $mode - $($found.Count) variant(s) below $Root" -ForegroundColor Cyan

$results = @()

foreach ($dir in $found) {
    $qpf     = (Get-ChildItem -Path $dir.FullName -Filter '*.qpf' -File | Select-Object -First 1)
    $project = [System.IO.Path]::GetFileNameWithoutExtension($qpf.Name)
    $qsf     = Join-Path $dir.FullName "$project.qsf"

    $family = ''
    $device = ''
    if (Test-Path $qsf) {
        $fLine = Select-String -Path $qsf -Pattern '-name FAMILY\s+"?([^"\r\n]+)"?' -List
        if ($fLine) { $family = $fLine.Matches[0].Groups[1].Value.Trim().Trim('"') }
        $dLine = Select-String -Path $qsf -Pattern '-name DEVICE\s+(\S+)' -List
        if ($dLine) { $device = $dLine.Matches[0].Groups[1].Value.Trim() }
    }

    $bin = Get-QuartusBin $family
    Write-Host ("  {0,-22} {1,-14} {2}" -f $dir.Name, $family, (Get-QuartusLabel $bin))

    $status = 'ok'
    $firstError = ''

    Push-Location $dir.FullName
    try {
        $steps = @()
        switch ($mode) {
            'map'  { $steps = @(@{exe='quartus_map.exe'; args=@($project)}) }
            'fit'  { $steps = @(@{exe='quartus_map.exe'; args=@($project)},
                                @{exe='quartus_fit.exe'; args=@($project)},
                                @{exe='quartus_sta.exe'; args=@($project)}) }
            'full' { $steps = @(@{exe='quartus_sh.exe';  args=@('--flow','compile',$project)}) }
        }

        foreach ($step in $steps) {
            $exe = Join-Path $bin $step.exe
            if (-not (Test-Path $exe)) {
                $status = 'quartus missing'; $firstError = $exe; break
            }
            $out = & $exe $step.args
            if ($LASTEXITCODE -ne 0) {
                $status = "FAILED ($($step.exe))"
                $err = $out | Select-String -Pattern '^Error \(' | Select-Object -First 1
                if ($err) { $firstError = $err.Line.Trim() }
                break
            }
        }
    }
    finally { Pop-Location }

    # Only evaluate the reports when the run was clean. Otherwise the numbers come
    # from an earlier build and claim something about code that could not even be
    # compiled just now.
    $le = $null; $mem = $null; $slk = $null; $warn = @()
    if ($status -eq 'ok') {
        $of = Join-Path $dir.FullName 'output_files'
        $warn = Get-WatchedWarnings (Join-Path $of "$project.map.rpt")
        if ($mode -eq 'map') {
            # Only the mapper ran - fit.rpt/sta.rpt would be from an earlier run
            $m = Select-String -Path (Join-Path $of "$project.map.rpt") `
                               -Pattern 'Implemented (\d+) logic cells' -List `
                               -ErrorAction SilentlyContinue
            if ($m) { $le = "$($m.Matches[0].Groups[1].Value) (synth.)" }
        }
        else {
            $le  = Get-ReportValue (Join-Path $of "$project.fit.rpt") 'Total logic elements'
            $mem = Get-ReportValue (Join-Path $of "$project.fit.rpt") 'Total memory bits'
            $slk = Get-WorstSlack  (Join-Path $of "$project.sta.rpt")
        }
    }

    # Baseline comparison - only meaningful with real fitter numbers.
    $delta = ''
    if ($status -eq 'ok' -and $mode -ne 'map' -and $baseline.ContainsKey($dir.Name)) {
        $b   = $baseline[$dir.Name]
        $leN = Get-FirstNumber $le
        $mmN = Get-FirstNumber $mem
        $bits = @()
        # Logic elements and memory bits must match exactly - they are a property of
        # the design, not of the run.
        if ($null -ne $leN -and $leN -ne [int]$b.LE)         { $bits += ("LE {0:+#;-#;0}" -f ($leN - [int]$b.LE)) }
        if ($null -ne $mmN -and $mmN -ne [int]$b.MemoryBits) { $bits += ("Mem {0:+#;-#;0}" -f ($mmN - [int]$b.MemoryBits)) }
        # Slack is placement dependent and jitters by a few hundred picoseconds
        # between runs of identical sources. Only a big move or an actually tight
        # result is worth reporting - anything else is noise that trains you to
        # ignore the whole column.
        if ($slk) {
            $d = [double]$slk - [double]$b.Slack
            if ([math]::Abs($d) -gt $SlackTolerance) { $bits += ("Slack {0:+0.000;-0.000}" -f $d) }
            elseif ([double]$slk -lt $SlackFloor)    { $bits += ("Slack only $slk ns") }
        }
        if ($bits) { $delta = $bits -join ', ' } else { $delta = '=' }
    }

    if ($status -ne 'ok')      { Write-Host "       -> $status" -ForegroundColor Red }
    elseif ($delta -and $delta -ne '=') { Write-Host "       -> ok, but baseline delta: $delta" -ForegroundColor Yellow }
    else                       { Write-Host '       -> ok' -ForegroundColor Green }
    foreach ($w in $warn)      { Write-Host "          $w" -ForegroundColor DarkYellow }

    $results += [pscustomobject]@{
        Variant  = $dir.Name
        Device   = $device
        Status   = $status
        LE       = $le
        Memory   = $mem
        Slack    = $slk
        Delta    = $delta
        Warnings = $warn.Count
        Error    = $firstError
    }
}

Write-Host ''
$results | Format-Table Variant, Device, Status, LE, Memory, Slack, Delta, Warnings -AutoSize

$bad = $results | Where-Object { $_.Status -ne 'ok' }
if ($bad) {
    Write-Host 'Errors:' -ForegroundColor Red
    $bad | ForEach-Object { Write-Host "  $($_.Variant): $($_.Error)" }
    exit 1
}
$drift = $results | Where-Object { $_.Delta -and $_.Delta -ne '=' }
if ($drift) {
    Write-Host 'Baseline drift:' -ForegroundColor Yellow
    $drift | ForEach-Object { Write-Host "  $($_.Variant): $($_.Delta)" }
    exit 2
}
Write-Host 'All variants clean.' -ForegroundColor Green
