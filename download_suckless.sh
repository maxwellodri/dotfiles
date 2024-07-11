#!/bin/bash
cd $SOURCE
echo "Working from directory $SOURCE"
git clone https://github.com/maxwellodri/st
git clone https://github.com/maxwellodri/dmenu
git clone https://github.com/maxwellodri/dwm
ssh-keygen -t rsa -f ~/.ssh/id_rsa
cd st/
git remote rm origin
git remote add origin git@github.com:maxwellodri/st.git
cd ../dwm
git remote rm origin
git remote add origin git@github.com:maxwellodri/dwm.git
cd ../dmenu
git remote rm origin
git remote add origin git@github.com:maxwellodri/dmenu.git
echo "Paste the contents of ~/.ssh/id_rsa.pub into https://github.com/settings/keys as a new ssh key"
echo "To push changes will need to push with: git push --set-upstream origin master"
exit 0
