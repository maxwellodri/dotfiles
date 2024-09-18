#!/bin/bash

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
  mount_point=$(findmnt --real --list | grep maxwellsecrets | awk '{print $1}')
  if [ -z "$mount_point" ]; then
    echo "Failed to find the mount point."
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
    echo "Creating an archive of tomb and key..."
    TAR_FILE="maxwellsecrets.tomb.tar.gz"
    tar -czf "$TAR_FILE" maxwellsecrets.tomb maxwellsecrets.tomb.key

    if [ $? -ne 0 ]; then
        echo "Error: Failed to create the tar archive."
        exit 1
    fi

    echo "Backing up tar archive to VPS..."
    rsync -avz --progress "$TAR_FILE" maxwell@donnie:~/backups/
    if [ $? -eq 0 ]; then
        echo "Successfully backed up tar archive to VPS."
    else
        echo "Error backing up tar archive to VPS."
    fi

    echo "Backing up tar archive to Dropbox..."
    dbxcli put "$TAR_FILE"
    if [ $? -eq 0 ]; then
        echo "Successfully backed up tar archive to Dropbox."
    else
        echo "Error backing up tar archive to Dropbox."
    fi
    rm "$TAR_FILE"
    echo "Backup complete, and local archive removed."
}

if [[ $# -eq 0 ]]; then
  echo "Error: At least one flag (--update or --backup) is required."
  exit 1
fi

update_flag=false
backup_flag=false

for arg in "$@"; do
  case $arg in
    --update)
      update_flag=true
      shift
      ;;
    --backup)
      backup_flag=true
      shift
      ;;
    *)
      echo "Unknown option: $arg"
      exit 1
      ;;
  esac
done

if [ "$update_flag" = true ]; then
  update
fi

if [ "$backup_flag" = true ]; then
  backup
fi
