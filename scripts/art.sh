#!/bin/bash
STRING="Krita\nGIMP"
PROGRAM="$(echo -e $STRING | dmenu -fn "Monospace-64:bold" -i)"
case "$PROGRAM" in
    "GIMP")     echo "Starting $PROGRAM"
                ;;
    "Krita")    echo "Starting $PROGRAM"
                Huion610ProTablet.sh "$PROGRAM" && krita 

                ;;

    *)
                echo -e "Pick from one of: $STRING"
                ;;
esac




