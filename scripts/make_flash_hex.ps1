<#
.SYNOPSIS
  Builds the Intel HEX file with the game ROMs for the configuration flash
  (HAS_FLASH_ROM, rtl/common/Flash_ROM.vhd).

.DESCRIPTION
  The SD card stays the one source of the game data. This script takes the slots of a
  card in the .22 format - either an image of the whole card or the 64 KByte slot files
  that make_sd.bat writes - and lays out the first 32 KByte of each slot in the flash:

      game n at 080000h + n * 8000h      (game 0..31 -> 080000h..17FFFFh)

  The CRC16-CCITT in the last two bytes of each slot is checked once here and reported;
  it does not go into the flash, Flash_ROM.vhd does not read one.

  Slots that are completely FF or 00 are left out, so that part of the flash stays
  erased - Flash_ROM.vhd then reports error 8 for that game instead of running it.

  THE RESULT CONTAINS COPYRIGHTED GAME ROMS. Write it below output_files\ (ignored by
  git) and never into bin\. variants\<name>\willfa7_roms.cof expects it at
  output_files\willfa7_roms.hex.

.PARAMETER Image
  Image of a WillFA7 SD card in the .22 format (raw sectors, game 0 at sector 660,
  128 sectors per game). Read for as many games as it holds, at most -Games.

.PARAMETER SlotFiles
  The 64 KByte slot files in game order, game 0 first, as add_crc16_move produces
  them. Instead of -Image.

.PARAMETER Out
  The .hex file to write.

.PARAMETER Games
  How many games at most. Default 32, which is what the switch debounce mask and the
  DIP selection cover.

.EXAMPLE
  .\make_flash_hex.ps1 -Image D:\willfa7_card.img -Out ..\variants\s_cyclone_iv_v4\output_files\willfa7_roms.hex
#>
param(
    [string]$Image,
    [string[]]$SlotFiles,
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Games = 32
)

$ErrorActionPreference = 'Stop'

# card layout, see FPGA_source\CLAUDE.md section 'SD-Karte'
$SlotBytes   = 65536
$FirstSector = 660
$PayloadBytes = 32768
# flash layout, see rtl/common/Flash_ROM.vhd
$FlashBase   = 0x080000
$FlashSlot   = 0x8000

if ((-not $Image) -and (-not $SlotFiles)) { throw 'Give -Image or -SlotFiles.' }
if ($Image -and $SlotFiles) { throw 'Give -Image or -SlotFiles, not both.' }

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public static class WillFAFlash {
    // CRC-16/CCITT-FALSE: poly 1021h, init FFFFh, MSB first - the same LFSR as
    // rtl/sound/crc16_ccitt.vhd and add_crc16_move.exe.
    public static ushort Crc(byte[] d, int off, int len) {
        ushort crc = 0xFFFF;
        for (int i = 0; i < len; i++) {
            crc ^= (ushort)(d[off + i] << 8);
            for (int b = 0; b < 8; b++)
                crc = (ushort)(((crc & 0x8000) != 0) ? ((crc << 1) ^ 0x1021) : (crc << 1));
        }
        return crc;
    }
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

# collect the slots as byte arrays
$slots = New-Object System.Collections.Generic.List[byte[]]
if ($Image) {
    $img = [System.IO.File]::ReadAllBytes((Resolve-Path $Image))
    for ($n = 0; $n -lt $Games; $n++) {
        $off = ($FirstSector * 512) + ($n * $SlotBytes)
        if ($off + $SlotBytes -gt $img.Length) { break }
        $s = New-Object byte[] $SlotBytes
        [Array]::Copy($img, $off, $s, 0, $SlotBytes)
        $slots.Add($s)
    }
} else {
    foreach ($f in $SlotFiles) {
        if ($slots.Count -ge $Games) { break }
        $s = [System.IO.File]::ReadAllBytes((Resolve-Path $f))
        if ($s.Length -ne $SlotBytes) { throw "$f is $($s.Length) bytes, a slot is $SlotBytes." }
        $slots.Add($s)
    }
}
if ($slots.Count -eq 0) { throw 'No slot found.' }

$sb = New-Object System.Text.StringBuilder
$written = 0
$warn = 0
for ($n = 0; $n -lt $slots.Count; $n++) {
    $s = $slots[$n]
    $addr = $FlashBase + $n * $FlashSlot
    if ([WillFAFlash]::Blank($s, 0, $PayloadBytes)) {
        Write-Host ('game {0,2}: empty, left out' -f $n) -ForegroundColor DarkGray
        continue
    }
    $calc = [WillFAFlash]::Crc($s, 0, $PayloadBytes)
    $read = ([int]$s[$SlotBytes - 2] -shl 8) -bor $s[$SlotBytes - 1]
    # reset vector of the MPU, slot offset 2FFEh = 7FFEh, which Flash_ROM.vhd checks
    $vec = ([int]$s[0x2FFE] -shl 8) -bor $s[0x2FFF]
    $line = 'game {0,2}: {1:X6}  crc {2:X4}  vector {3:X4}' -f $n, $addr, $calc, $vec
    if ($calc -ne $read) {
        Write-Host ('{0}  CRC MISMATCH, card says {1:X4}' -f $line, $read) -ForegroundColor Yellow
        $warn++
    } elseif ($vec -eq 0xFFFF) {
        Write-Host ('{0}  vector FFFF - Flash_ROM will report error 8' -f $line) -ForegroundColor Yellow
        $warn++
    } else {
        Write-Host $line
    }
    [WillFAFlash]::Data($sb, $addr, $s, 0, $PayloadBytes)
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
