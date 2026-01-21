#!/bin/bash

# Opens the iOS Simulator's Files app local storage directory
# This is where files saved to "On My iPhone" in the Files app are stored

path=$(xcrun simctl listapps booted 2>/dev/null | plutil -convert json -o - - | jq -r '."com.apple.DocumentsApp".GroupContainers."group.com.apple.FileProvider.LocalStorage"')

if [ -z "$path" ] || [ "$path" = "null" ]; then
    echo "Error: Could not find Files app storage path. Is a simulator booted?"
    exit 1
fi

echo "Opening: $path"
open "$path"
