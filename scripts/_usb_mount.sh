#!/bin/sh

. "${XDG_CONFIG_HOME:-$HOME/.config}/sh/shutil.sh"

whitelist_uuids=(
  "B95B-0965"
  "18459b9d-6933-4667-827a-d8f49e24926d"
  "fbe2dc60-e51e-47b3-95f2-d04010f4d385"
  "60d700a8-5282-450d-95f7-597c53bad759"
  "665431205430F481"
  "6A2C-40AD"
  "6fb585ac-0a92-477a-822a-86af32fd4911"
)

dmenu=$(get_dmenu)

action=$(printf "Mount\nUnmount" | "$dmenu")

get_mounted_uuids() {
  mount | grep "^/dev/" | awk '{print $1}' | xargs -I{} run_elevated blkid {} | grep -o 'UUID="[^"]*"' | cut -d'"' -f2
}

get_unmounted_uuids() {
  run_elevated blkid | grep -v "$(get_mounted_uuids | tr '\n' '|' | sed 's/|$//')" | grep -o 'UUID="[^"]*"' | cut -d'"' -f2
}

filter_whitelisted() {
  grep -v -F "$(printf "%s\n" "${whitelist_uuids[@]}")"
}

case "$action" in
  Mount)
    unmounted_uuids=$(get_unmounted_uuids | filter_whitelisted)
    if [ -n "$unmounted_uuids" ]; then
      device_to_mount=$(echo "$unmounted_uuids" | "$dmenu")
      if [ -n "$device_to_mount" ]; then
        device_path=$(run_elevated blkid | grep "$device_to_mount" | cut -d: -f1)
        run_elevated mount "$device_path" /mnt
      fi
    else
      notify-send "No unmounted devices available."
    fi
    ;;
  Unmount)
    mounted_uuids=$(get_mounted_uuids | filter_whitelisted)
    if [ -n "$mounted_uuids" ]; then
      device_to_unmount=$(echo "$mounted_uuids" | "$dmenu")
      if [ -n "$device_to_unmount" ]; then
        device_path=$(run_elevated blkid | grep "$device_to_unmount" | cut -d: -f1)
        run_elevated umount "$device_path"
      fi
    else
      notify-send "No mounted devices available."
    fi
    ;;
esac
