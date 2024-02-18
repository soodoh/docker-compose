#!/bin/bash

SOURCE_BASE_DIR="/sources"
BACKUP_BASE_DIR="/backups"
BACKUP_FOLDER=$(date +'%Y-%m-%d_backup')
BACKUP_PATH="$BACKUP_BASE_DIR/$BACKUP_FOLDER"

if [ -d "$RESTORE_DIR" ]; then
  # BEGIN: Logic to restore volumes
  for BACKUP in "$RESTORE_DIR"/*/; do
    SOURCE_FOLDER=$(basename "$BACKUP")
    if [ -d "$SOURCE_BASE_DIR/$SOURCE_FOLDER" ]; then
      echo "Clearing contents in '$SOURCE_BASE_DIR/$SOURCE_FOLDER'"
      rm -rf "$SOURCE_BASE_DIR/$SOURCE_FOLDER/*"
      echo "Restoring '$SOURCE_FOLDER'..."
      cp -r "$BACKUP"/* "$SOURCE_BASE_DIR/$SOURCE_FOLDER/"
    else
      echo "Could not find corresponding '$SOURCE_FOLDER' in '$SOURCE_BASE_DIR/'!"
      echo "$SOURCE_FOLDER was skipped!"
    fi
  done
else 
  # BEGIN: Logic to backup volumes
  if [ -d "$BACKUP_PATH" ]; then
    echo "$BACKUP_FOLDER already exists! Replacing with new backup..."
    rm -rf "$BACKUP_PATH"
  fi
  # Make sure backup directory exists
  mkdir -p "$BACKUP_PATH";
  # Copy all volumes (mounted to /sources/*)
  for SOURCE in "$SOURCE_BASE_DIR"/*/; do
    SOURCE_FOLDER=$(basename "$SOURCE")
    echo "Backing up $SOURCE_FOLDER..."
    cp -rp "$SOURCE" "$BACKUP_PATH"
    echo "Done!"
  done
fi

echo "Finished!!!"
