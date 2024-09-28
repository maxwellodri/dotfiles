#!/bin/bash
cd $SOURCE
echo "Working from directory $SOURCE"

declare -A REPO_EXISTS
REPOS=("st" "dmenu" "dwm" "slock")

# Check if directories exist at start
for repo in "${REPOS[@]}"; do
    if [ -d "$repo" ]; then
        REPO_EXISTS["$repo"]=1
        echo "Directory '$repo' exists at the start of the script."
    else
        REPO_EXISTS["$repo"]=0
    fi
done

# Clone repositories and set remotes if the directory did not exist
for repo in "${REPOS[@]}"; do
    if [ "${REPO_EXISTS[$repo]}" -eq 1 ]; then
        echo "Skipping cloning and remote setup for '$repo' as directory exists."
    else
        git clone "https://github.com/maxwellodri/$repo"
        cd "$repo"
        git remote rm origin
        git remote add origin "git@github.com:maxwellodri/$repo.git"
        cd ..
    fi
done

GENERATE_KEY=-1
KEY_FILE=~/.ssh/id_ed25519

if [ ! -f "$KEY_FILE" ]; then
    ssh-keygen -t rsa -f "$KEY_FILE"
    GENERATE_KEY=1
else
    echo "Skipping ssh-keygen as $KEY_FILE appears to exist."
    GENERATE_KEY=0
fi

if [ "$GENERATE_KEY" -eq 1 ]; then
    echo "Paste the contents of $KEY_FILE.pub into https://github.com/settings/keys as a new SSH key."
fi

echo "To push changes, you will need to use: git push --set-upstream origin master"
exit 0
