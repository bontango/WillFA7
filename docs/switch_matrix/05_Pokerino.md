== Pokerino ==

Williams ''Pokerino'' (1978), System 4. 46 belegte Schalter, Matrix 6 x 8.

=== Switch Matrix ===

{| class="wikitable"
!  !! Column 1<br />GRN-BRN !! Column 2<br />GRN-RED !! Column 3<br />GRN-ORN !! Column 4<br />GRN-YEL !! Column 5<br />GRN-BLK !! Column 6<br />GRN-BLU
|-
! Return 1<br />WHT-BRN
| 01 Plumb Bob Tilt || 09 Top Left Lane Star Rollover || 17 Diamond Queen Drop Target || 25 Heart Jack Drop Target || 33 Diamond Jack Drop Target || 41 Ten Star Rollover
|-
! Return 2<br />WHT-RED
| 02 Ball Roll Tilt || 10 Captive Ball Star Rollover || 18 Club Queen Drop Target || 26 Spade Jack Drop Target || 34 Club Jack Drop Target || 42 Joker Drop Target
|-
! Return 3<br />WHT-ORN
| 03 Credit Button || 11 Top Left Standup || 19 Heart Queen Drop Target || 27 Right Special Rollover || 35 Jack Drop Target Series || 43 Inner Flipper
|-
! Return 4<br />WHT-YEL
| 04 Right Coin Switch || 12 Spade Ace Star Rollover || 20 Spade Queen Drop Target || 28 Right Kicker || 36 Spinner || 44 Outer Flipper
|-
! Return 5<br />WHT-GRN
| 05 Center Coin Switch || 13 Heart Ace Star Rollover || 21 Queen Drop Target Series || 29 Outhole || 37 Upper Left Standup || 45 Left Jack Drop Target Standup
|-
! Return 6<br />WHT-BLU
| 06 Left Coin Switch || 14 Club Ace Star Rollover || 22 Queen Drop Target Standup || 30 Left Kicker || 38 Top Jet Bumper || 46 Right Jack Drop Target Standup
|-
! Return 7<br />WHT-VIO
| 07 Slam Tilt || 15 Diamond Ace Star Rollover || 23 Right Center Standup || 31 Left Special Rollover || 39 Left Jet Bumper || 47 Not Used
|-
! Return 8<br />WHT-GRY
| 08 High Score Reset || 16 Top Right Lane Star Rollover || 24 Playfield Tilt || 32 Bottom Left Standup || 40 Bottom Jet Bumper || 48 Not Used
|}

Columns 7 und 8 sind unbelegt (Switches 49-64).

=== Quelle ===

Schalterbelegung: Original-Handbuchblatt ''Pokerino'', Figure 9 "POKERINO Switch Matrix".
Gegengeprueft an der Dispatch-Tabelle des Spiel-ROMs ($609C, 2 Bytes/Switch): die vier
Queen-Drop-Targets 17-20 sowie die Jack-Drop-Targets 25/26/33/34 teilen sich Handler
$617E, die fuenf Standups 23/32/37/45/46 den Handler $6188, die beiden Kicker 28/30
den Handler $61B6, die drei Jet Bumper 38/39/40 den Handler $61FC - jede Gruppe
einheitlich.

Kabelfarben: bei Williams System 3-7 einheitlich; belegt durch die Original-Handbuchblaetter von ''Contact'' (System 3, 1978, alle acht Spalten und Zeilen) und ''Laser Ball'' (System 6, 1979, Spalten 2-8), die identisch sind.
