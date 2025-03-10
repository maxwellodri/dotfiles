#!/bin/bash

cd ~/Documents/backup/

if [ ! -f "maxwellsecrets.tomb" ]; then
    echo "Error: maxwellsecrets.tomb not found."
    exit 1
fi

if [ ! -f "maxwellsecrets.tomb.key" ]; then
    echo "Error: maxwellsecrets.tomb.key not found."
    exit 1
fi

update() {
    tomb open maxwellsecrets.tomb -k maxwellsecrets.tomb.key
    if [ $? -ne 0 ]; then
        exit 1 #password not supplied
    fi

    mount_point=$(findmnt --real --list | grep maxwellsecrets | awk '{print $1}')
    if [ -z "$mount_point" ]; then
        echo "Failed to find the mount point for tomb."
        # Check if pacman exists and is in PATH
        if command -v pacman >/dev/null 2>&1; then
            # Get running kernel version
            running_kernel=$(uname -r)
            # Get installed kernel version
            installed_kernel=$(pacman -Qi linux | grep Version | awk '{print $3}')

            if [ "$running_kernel" != "$installed_kernel" ]; then
                echo "Kernel version mismatch detected:"
                echo "Running kernel:    $running_kernel"
                echo "Installed kernel:  $installed_kernel"
                echo "Please reboot your system to use the new kernel."
            fi

            exit 1
        fi

        echo "Tomb is mounted at: $mount_point"

        if [ -f "$mount_point/update.sh" ]; then
            bash "$mount_point/update.sh"
        else
            echo "Script update.sh not found in the tomb."
        fi
        tomb close maxwellsecrets
        echo "Tomb has been updated"
}


    backup() {
        local paths=("$@")  # Accepts a list of paths as arguments
        echo "Creating an archive of tomb and key..."
        TAR_FILE="maxwellsecrets.tomb.tar.gz"
        tar -czf "$TAR_FILE" maxwellsecrets.tomb maxwellsecrets.tomb.key

        if [ $? -ne 0 ]; then
            echo "Error: Failed to create the tar archive."
            exit 1
        fi

        for path in "${paths[@]}"; do
            if [[ "$path" == "dropbox" ]]; then
                echo "Backing up tar archive to Dropbox..."
                dbxcli put "$TAR_FILE"
                if [ $? -eq 0 ]; then
                    echo "Successfully backed up tar archive to Dropbox."
                else
                    echo "Error backing up tar archive to Dropbox."
                fi
            else
                echo "Backing up tar archive to $path..."

            # Check if the path is local or remote
            if [[ -e "$path" ]]; then
                # Local path, check for root permissions if necessary
                if [[ ! -w "$path" ]]; then
                    sudo rsync -avz --progress "$TAR_FILE" "$path"
                else
                    rsync -avz --progress "$TAR_FILE" "$path"
                fi
            else
                #remote
                rsync -avz --progress "$TAR_FILE" "$path"
                if [ $? -eq 0 ]; then
                    echo "Successfully backed up tar archive to $path."
                else
                    echo "Error backing up tar archive to $path."
                fi
                fi
            fi
        done

        rm "$TAR_FILE"
        echo "Backup complete, and local archive removed."
    }


    if [[ $# -eq 0 ]]; then
        echo "Error: At least one flag (--update or --backup) is required."
        exit 1
    fi

    update_flag=false
    backup_flag=false
    dropbox_flag=true
    device=""
    paths=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --update)
                update_flag=true
                shift
                ;;
            --backup)
                backup_flag=true
                paths+=("maxwell@donnie:~/backups/")  # Path to VPS
                shift
                ;;
            --dev | --path)
                if [ -n "$2" ] && [[ "$2" != --* ]]; then
                    device="$2"
                    # Translate device to mount point
                    mountpoint=$(findmnt -n -o TARGET "$device")

                    if [ -n "$mountpoint" ]; then
                        paths+=("$mountpoint")
                    elif [[ -e "$device" ]]; then
                        paths+=("$device")
                    else
                        echo "Error: Device $device is not mounted."
                        exit 1
                    fi

                    shift 2
                else
                    echo "Error: "$1" flag requires a path/device argument."
                    exit 1
                fi
                ;;
            --nodropbox)
                dropbox_flag=false
                shift
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    if [ "$dropbox_flag" = true ]; then
        paths+=("dropbox")
    fi

    if [ "$update_flag" = true ]; then
        update
    fi

    if [ "$backup_flag" = true ]; then
        backup "${paths[@]}"  # Pass the list of paths to backup()
    fi
