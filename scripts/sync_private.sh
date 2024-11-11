#!/bin/bash

# Change to the source private directory
cd "$SOURCE/private/" || {
    notify-send "Autocommit Error" "Could not change to directory $SOURCE/private/"
    exit 1
}

# Run autocommit.sh and capture its output and exit status
output=$(./autocommit.sh 2>&1)
exit_status=$?

# Check if the command succeeded or failed
if [ $exit_status -ne 0 ]; then
    # Failed - send notification with error message
    notify-send "Autocommit Failed" "$output"
else
    # Success - send success notification
    notify-send "Autocommit Success" "autocommit.sh completed successfully"
fi

# Return the same exit status as autocommit.sh
exit $exit_status
