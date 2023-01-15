#!/bin/bash

# Set the hostname and username of the server
HOSTNAME=odri.net.au
USERNAME=root

# Connect to the server and run the `docker images` command to list the images
ssh "$USERNAME@$HOSTNAME" 'docker images'

# Extract the list of image names and tags from the output of the `docker images` command
# and store them in an array
IMAGE_TAGS=($(ssh "$USERNAME@$HOSTNAME" 'docker images' | tail -n +2 | awk '{print $1 ":" $2}'))

# Iterate over the array of image names and tags and check for updates
for IMAGE_TAG in "${IMAGE_TAGS[@]}"; do
  # Check for updates to the image by running the `docker pull` command
  ssh "$USERNAME@$HOSTNAME" "docker pull $IMAGE_TAG"

  # Get the current image id and the updated image id
  CURRENT_IMAGE_ID=$(ssh "$USERNAME@$HOSTNAME" "docker images -q $IMAGE_TAG")
  UPDATED_IMAGE_ID=$(ssh "$USERNAME@$HOSTNAME" "docker images -q $IMAGE_TAG")

  # If the image id has changed, it means an update was available
  if [ "$CURRENT_IMAGE_ID" != "$UPDATED_IMAGE_ID" ]; then
    # Use notify-send to display a notification
    notify-send "Docker Update Available" "An update was available for $IMAGE_TAG"
  fi
done
