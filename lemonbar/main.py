#!/bin/env python3
from time import localtime, strftime, sleep
import os
import psutil
def time():
    return 'T: '+strftime("%a-%d-%b %R", localtime()) #🕒 
def battery():
    bat = psutil.sensors_battery()
    return ''
def wifi():
    return ''
def main():
    tag = os.getenv('dotfiles_tag')
    while True:
        txt = ''
        for fn in tagdict[tag]:
            txt += fn()
        print(txt)
        sleep(1)
if __name__ == "__main__":
    tagdict = {"thinkpad": [time, battery, wifi], "pc": [time]}
    main()
