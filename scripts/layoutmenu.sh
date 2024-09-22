#!/bin/sh

cat <<EOF | xmenu -i
 0 [T] Tiled
 1 [M] Monocle
 2 [@] Spiral
 3 [W] Dwindle
 4 [D] Deck
 5 [S] BStack
 6 [U] BStackH
 7 [g] Grid
 8 [G] NrowGrid
 9 [-] HorizGrid
10 ::: GaplessGrid
11 |F| CenteredMaster
12 >F> centeredfloatingmaster
12 ><> Floating
EOF
