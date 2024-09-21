#!/bin/bash
cd $SOURCE
echo "Working from directory $SOURCE"
git clone https://github.com/maxwellodri/st
git clone https://github.com/maxwellodri/dmenu
git clone https://github.com/maxwellodri/dwm
git clone https://github.com/maxwellodri/slock
GENERATE_KEY=-1
KEY_FILE=~/.ssh/id_ed25519
[ ! -f "$KEY_FILE" ] && ssh-keygen -t rsa -f "$KEY_FILE" && GENERATE_KEY=1
[ -f "$KEY_FILE" ] && echo "Skipping ssh-keygen as $KEY_FILE appears to exist" && GENERATE_KEY=0
cd st/
git remote rm origin
git remote add origin git@github.com:maxwellodri/st.git
cd ../dwm
git remote rm origin
git remote add origin git@github.com:maxwellodri/dwm.git
cd ../dmenu
git remote rm origin
git remote add origin git@github.com:maxwellodri/dmenu.git
cd ../slock
git remote rm origin
git remote add origin git@github.com:maxwellodri/slock.git
[ "$GENERATE_KEY" == "1" ] && echo "Paste the contents of $KEY_FILE.pub into https://github.com/settings/keys as a new ssh key"
echo "To push changes will need to push with: git push --set-upstream origin master"
exit 0
