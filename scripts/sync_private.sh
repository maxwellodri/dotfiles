#!/bin/bash

# Change to the source private directory
cd "$SOURCE/private/" || {
    notify-send "Autocommit Error" "Could not change to directory $SOURCE/private/"
    exit 1
}

# Run autocommit.sh and capture its output and exit status
output=$(./autocommit.sh 2>&1)
exit_status=$?

# Check if the output contains indicators of nothing to commit
if echo "$output" | grep -q "nothing to commit" || \
   echo "$output" | grep -q "no changes added to commit" || \
   echo "$output" | grep -q "working tree clean"; then
    # Nothing to commit - this is a normal situation
    notify-send "Autocommit Info" "No changes to commit"
    exit 0
elif [ $exit_status -ne 0 ]; then
    # Real error occurred
    notify-send "Autocommit Failed" "$output"
    exit $exit_status
else
    # Success with actual commits
    notify-send "Autocommit Success" "Changes committed successfully"
    exit 0
fi
