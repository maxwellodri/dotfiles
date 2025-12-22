#!/bin/sh
#Launch the script just before launching GIMP/Krita etc rather than with Xorg , first argument to be different profiles
case "$1" in
    "debug")
                echo "Not setting pad buttons for tablet"
                ;;
    *)
                echo "Setting Default buttons..."
                xsetwacom --set 'HUION Huion Tablet Pad pad' Button 1 "key +ctrl +z -z -ctrl"
                xsetwacom --set 'HUION Huion Tablet Pad pad' Button 2 "key e"
                xsetwacom --set 'HUION Huion Tablet Pad pad' Button 3 "key Menu"
                xsetwacom --set 'HUION Huion Tablet Pad pad' Button 8 "key z"
                xsetwacom --set 'HUION Huion Tablet Pad pad' Button 9 "key w"
                xsetwacom --set 'HUION Huion Tablet Pad pad' Button 10 "key ]"
                xsetwacom --set 'HUION Huion Tablet Pad pad' Button 11 "key ["
                xsetwacom --set 'HUION Huion Tablet Pad pad' Button 12 "key Tab"
                echo "Done"
                ;;
esac

#HUION Huion Tablet Pen stylus      id: xx  type: STYLUS
#HUION Huion Tablet Pad pad         id: yy  type: PAD

