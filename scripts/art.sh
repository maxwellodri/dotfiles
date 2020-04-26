#!/bin/bash
STRING="Krita\nGIMP"
PROGRAM="$(echo -e $STRING | dmenu -l 10 -fn "Monospace-32:bold" -i)"
case "$PROGRAM" in
    "GIMP")     echo "Starting $PROGRAM"
                Huion610ProTablet.sh "$PROGRAM" && gimp
                ;;

    "Krita")    echo "Starting $PROGRAM"
                Huion610ProTablet.sh "$PROGRAM" && krita 

                ;;

    *)
                echo -e "Pick from one of: $STRING"
                ;;
esac




