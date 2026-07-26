== Phoenix ==

Williams ''Phoenix'' (1978), System 4. 46 belegte Schalter, Matrix 6 x 8.

=== Switch Matrix ===

{| class="wikitable"
!  !! Column 1<br />GRN-BRN !! Column 2<br />GRN-RED !! Column 3<br />GRN-ORN !! Column 4<br />GRN-YEL !! Column 5<br />GRN-BLK !! Column 6<br />GRN-BLU
|-
! Return 1<br />WHT-BRN
| 01 Plumb Bob Tilt || 09 "1" Rollover || 17 Center Jet Bumper || 25 Left Bank, Top Drop Target || 33 Left Center Drop Target || 41 Right Bank, Top Drop Target
|-
! Return 2<br />WHT-RED
| 02 Ball Roll Tilt || 10 "2" Rollover || 18 Left Jet Bumper || 26 Left Bank, Top Center Drop Target || 34 Not Used || 42 Right Bank, Top Center Drop Target
|-
! Return 3<br />WHT-ORN
| 03 Credit Button || 11 "3" Rollover || 19 Left Target || 27 Left Bank, Bottom Center Drop Target || 35 Right Center Drop Target || 43 Right Bank, Center Drop Target
|-
! Return 4<br />WHT-YEL
| 04 Right Coin Switch || 12 "4" Rollover || 20 Left Standup || 28 Left Bank, Bottom Drop Target || 36 Not Used || 44 Right Bank, Bottom Drop Target
|-
! Return 5<br />WHT-GRN
| 05 Center Coin Switch || 13 "5" Rollover || 21 Bull's-Eye Target || 29 Left Bank Drop Target Series || 37 Outhole || 45 Right Bank Drop Target Series
|-
! Return 6<br />WHT-BLU
| 06 Left Coin Switch || 14 Right Target || 22 Left Bank Standup || 30 Left Kicker || 38 Top Right Standup || 46 Right Kicker
|-
! Return 7<br />WHT-VIO
| 07 Slam Tilt || 15 Spinner || 23 Playfield Tilt || 31 Left Inside Rollover || 39 Bottom Left Standup || 47 Right Inside Rollover
|-
! Return 8<br />WHT-GRY
| 08 High Score Reset* || 16 Right Jet Bumper || 24 Right Bank Standup || 32 Left Outside Rollover || 40 Bottom Right Standup || 48 Right Outside Rollover
|}

<nowiki>*</nowiki> Laut Handbuchblatt: "High score reset not provided on prototype games."

Columns 7 und 8 sind unbelegt (Switches 49-64).

=== Quelle ===

Schalterbelegung: Original-Handbuchblatt ''Phoenix'', Figure 9 "PHOENIX Switch Matrix".

Das Handbuchblatt korrigiert die Pinitech-Datenbank an zwei Stellen: dort sind Switch 27
und Switch 43 als "not used" gefuehrt. Tatsaechlich sind beide Drop Targets - jede der
beiden Banks hat vier Targets, nicht drei. Die Dispatch-Tabelle des Spiel-ROMs ($609C,
2 Bytes/Switch) bestaetigt das unabhaengig: die Switches 25/26/27/28 und 41/42/43/44
teilen sich alle acht denselben Handler $619E. Weitere Gegenproben: die Center Drop
Targets 33/35 teilen $61D8, die drei Standups 38/39/40 teilen $61F0, die tatsaechlich
unbelegten Switches 34/36 zeigen auf den Leerlauf-Handler $6343.

Kabelfarben: bei Williams System 3-7 einheitlich; belegt durch die Original-Handbuchblaetter von ''Contact'' (System 3, 1978, alle acht Spalten und Zeilen) und ''Laser Ball'' (System 6, 1979, Spalten 2-8), die identisch sind.
