<#
.SYNOPSIS
  Builds the Intel HEX file with the game ROMs for the configuration flash
  (HAS_FLASH_ROM, rtl/common/Flash_ROM.vhd).

.DESCRIPTION
  The SD card stays the one source of the game data. This script takes it in the x.30
  layout (image version 4, written by make_sd.bat) - either an image of the whole card
  or the files that make_sd.bat writes - and lays it out in the flash:

      card    sector 660 + n * 24     game n, 12 KByte MPU ROMs
              sector 1428 + n * 40    game n, 20 KByte sound board ROMs
      flash   080000h + n * 8000h     game n, MPU ROMs, then sound board ROMs (32 KByte)

  With -CycloneII the flash is an EPCS4 (512 KByte) and the board has no rom0, so the
  slot is compact - only the 10 KByte of ROM addresses 0800h..2FFFh:

      flash   030000h + n * 2800h     game n, MPU ROMs from 0800h (10 KByte)

  An x.20 Cyclone IV card (image version 2.1) has the MPU part only; with that the
  sound half of each flash slot stays FF, which is fine for every board without a
  sound board. Use -NoSound for such a card, otherwise whatever lies behind slot 31
  is taken for sound data.

  Games whose MPU part is completely FF or 00 are left out, so that part of the flash
  stays erased - Flash_ROM.vhd then reports error 8 for that game instead of running it.

  THE RESULT CONTAINS COPYRIGHTED GAME ROMS. Write it below output_files\ (ignored by
  git) and never into bin\. variants\<name>\willfa7_roms.cof expects it at
  output_files\willfa7_roms.hex.

.PARAMETER Image
  Image of a WillFA7 SD card (raw sectors). Read for as many games as it holds, at
  most -Games.

.PARAMETER SlotFiles
  The 12 KByte MPU files in game order, game 0 first, as make_sd.bat writes them.
  Instead of -Image.

.PARAMETER SoundFiles
  With -SlotFiles: the 20 KByte sound files in the same order. Optional.

.PARAMETER NoSound
  With -Image: read the MPU part only (x.20 card, or a board without sound board).

.PARAMETER CycloneII
  The compact EPCS4 layout of the Cyclone II board (FL_BASE etc. in top/WillFA7.vhd).
  Implies -NoSound.

.PARAMETER Out
  The .hex file to write.

.PARAMETER Games
  How many games at most. Default 32, which is what the switch debounce mask and the
  DIP selection cover.

.EXAMPLE
  .\make_flash_hex.ps1 -Image D:\willfa7_card.img -Out ..ariants\s_cyclone_iv_v4\output_files\willfa7_roms.hex
#>
param(
    [string]$Image,
    [string[]]$SlotFiles,
    [string[]]$SoundFiles,
    [switch]$NoSound,
    [switch]$CycloneII,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Games = 32
)

$ErrorActionPreference = 'Stop'

# card layout, see top/WillFA7.vhd (SD_SLOT_SECTORS, SD_SOUND_SECTOR) and SD_Card.vhd v13
$FirstSector  = 660
$MpuBytes     = 12288     # 24 sectors
$SoundSector  = 1428      # 660 + 32 * 24
$SoundBytes   = 20480     # 40 sectors
# flash layout, see rtl/common/Flash_ROM.vhd
$FlashBase    = 0x080000
$FlashSlot    = 0x8000
$SlotFirst    = 0         # first byte of the 32 KByte game slot that goes into the flash
if ($CycloneII) {
    $FlashBase = 0x030000
    $FlashSlot = 0x2800
    $SlotFirst = 0x0800   # no rom0 on this board
    $NoSound   = $true
}

if ((-not $Image) -and (-not $SlotFiles)) { throw 'Give -Image or -SlotFiles.' }
if ($Image -and $SlotFiles) { throw 'Give -Image or -SlotFiles, not both.' }

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public static class WillFAFlash {
    public static bool Blank(byte[] d, int off, int len) {
        byte f = d[off];
        if (f != 0xFF && f != 0x00) return false;
        for (int i = 1; i < len; i++) if (d[off + i] != f) return false;
        return true;
    }
    static void Rec(StringBuilder sb, int type, int addr, byte[] d, int off, int len) {
        int sum = len + ((addr >> 8) & 0xFF) + (addr & 0xFF) + type;
        sb.AppendFormat(":{0:X2}{1:X4}{2:X2}", len, addr & 0xFFFF, type);
        for (int i = 0; i < len; i++) { sb.AppendFormat("{0:X2}", d[off + i]); sum += d[off + i]; }
        sb.AppendFormat("{0:X2}\r\n", (-sum) & 0xFF);
    }
    // Intel HEX with type 04 records for the upper address half, absolute addresses.
    public static void Data(StringBuilder sb, int addr, byte[] d, int off, int len) {
        int upper = -1;
        for (int p = 0; p < len; p += 16) {
            int a = addr + p;
            if ((a >> 16) != upper) {
                upper = a >> 16;
                Rec(sb, 4, 0, new byte[] { (byte)(upper >> 8), (byte)upper }, 0, 2);
            }
            Rec(sb, 0, a, d, off + p, Math.Min(16, len - p));
        }
    }
    public static void End(StringBuilder sb) { Rec(sb, 1, 0, new byte[0], 0, 0); }
}
'@

# collect each game as one 32 KByte flash slot: MPU part, then sound part (FF if none)
function New-Slot {
    $s = New-Object byte[] ($MpuBytes + $SoundBytes)
    for ($i = 0; $i -lt $s.Length; $i++) { $s[$i] = 0xFF }
    return ,$s
}
$slots = New-Object System.Collections.Generic.List[byte[]]
$soundCount = 0
if ($Image) {
    $img = [System.IO.File]::ReadAllBytes((Resolve-Path $Image))
    for ($n = 0; $n -lt $Games; $n++) {
        $off = ($FirstSector * 512) + ($n * $MpuBytes)
        if ($off + $MpuBytes -gt $img.Length) { break }
        $s = New-Slot
        [Array]::Copy($img, $off, $s, 0, $MpuBytes)
        $soff = ($SoundSector * 512) + ($n * $SoundBytes)
        if ((-not $NoSound) -and ($soff + $SoundBytes -le $img.Length)) {
            [Array]::Copy($img, $soff, $s, $MpuBytes, $SoundBytes)
            $soundCount++
        }
        $slots.Add($s)
    }
} else {
    for ($n = 0; $n -lt $SlotFiles.Count -and $n -lt $Games; $n++) {
        $m = [System.IO.File]::ReadAllBytes((Resolve-Path $SlotFiles[$n]))
        if ($m.Length -ne $MpuBytes) { throw "$($SlotFiles[$n]) is $($m.Length) bytes, an MPU part is $MpuBytes." }
        $s = New-Slot
        [Array]::Copy($m, 0, $s, 0, $MpuBytes)
        if ($SoundFiles -and $n -lt $SoundFiles.Count) {
            $snd = [System.IO.File]::ReadAllBytes((Resolve-Path $SoundFiles[$n]))
            if ($snd.Length -ne $SoundBytes) { throw "$($SoundFiles[$n]) is $($snd.Length) bytes, a sound part is $SoundBytes." }
            [Array]::Copy($snd, 0, $s, $MpuBytes, $SoundBytes)
            $soundCount++
        }
        $slots.Add($s)
    }
}
if ($slots.Count -eq 0) { throw 'No game found.' }

$sb = New-Object System.Text.StringBuilder
$written = 0
$warn = 0
for ($n = 0; $n -lt $slots.Count; $n++) {
    $s = $slots[$n]
    $addr = $FlashBase + $n * $FlashSlot
    if ([WillFAFlash]::Blank($s, $SlotFirst, $MpuBytes - $SlotFirst)) {
        Write-Host ('game {0,2}: empty, left out' -f $n) -ForegroundColor DarkGray
        continue
    }
    # reset vector of the MPU, slot offset 2FFEh = 7FFEh, which Flash_ROM.vhd checks
    $vec = ([int]$s[0x2FFE] -shl 8) -bor $s[0x2FFF]
    $snd = if ([WillFAFlash]::Blank($s, $MpuBytes, $SoundBytes)) { 'no sound' } else { 'sound' }
    $line = 'game {0,2}: {1:X6}  vector {2:X4}  {3}' -f $n, $addr, $vec, $snd
    if ($vec -eq 0xFFFF) {
        Write-Host ('{0}  - Flash_ROM will report error 8' -f $line) -ForegroundColor Yellow
        $warn++
    } else {
        Write-Host $line
    }
    if ($CycloneII) { $len = $MpuBytes - $SlotFirst } else { $len = $s.Length }
    [WillFAFlash]::Data($sb, $addr, $s, $SlotFirst, $len)
    $written++
}
[WillFAFlash]::End($sb)

if ([System.IO.Path]::IsPathRooted($Out)) { $outFull = $Out }
else { $outFull = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Out)) }
$dir = Split-Path $outFull
if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir }
[System.IO.File]::WriteAllText($outFull, $sb.ToString(), (New-Object System.Text.ASCIIEncoding))
Write-Host ('{0} games written to {1}' -f $written, $outFull)
if ($warn -gt 0) { Write-Host ('{0} warning(s), see above' -f $warn) -ForegroundColor Yellow }
