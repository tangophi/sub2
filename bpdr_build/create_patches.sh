#!/bin/bash

# This script creates patch files from commits in the sub2 submodule.
# It groups commits by an ID in the commit message (e.g., [ABCD-123])
# and creates one patch file per ID.

set -e

# The directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The root directory of the sub2 submodule
SUB2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# The directory where patches will be stored
PATCHES_DIR="$SUB2_DIR/patches"

# Associative array to store commit hashes grouped by ID
declare -A commit_groups

# Associative array to store the first commit message for each ID
declare -A first_commit_messages

echo "Navigating to $SUB2_DIR"
cd "$SUB2_DIR"

# Get the list of commits to process.
commits=$(git log --pretty=format:"%H %s")

echo "Processing commits..."
while read -r commit_hash commit_message; do
    # Extract the ID from the commit message (e.g., [ABCD-123])
    id=$(echo "$commit_message" | grep -oE '\[[A-Z]+-[0-9]+\]' || true)

    if [ -n "$id" ]; then
        echo "Found commit with ID $id: $commit_hash $commit_message"
        # If this is the first time we see this ID, store the commit message
        if [ -z "${first_commit_messages[$id]}" ]; then
            first_commit_messages["$id"]="$commit_message"
        fi

        # Add the commit hash to the group for this ID
        if [ -n "${commit_groups[$id]}" ]; then
            commit_groups["$id"]="${commit_groups[$id]} $commit_hash"
        else
            commit_groups["$id"]="$commit_hash"
        fi
    fi
done <<< "$commits"

echo "Creating patches..."
# Find the latest patch number in the patches directory
latest_patch_num=$(ls -1 "$PATCHES_DIR" | grep -oE '^[0-9]{4}' | sort -n | tail -n 1 | sed 's/^0*//' || true)
if [ -z "$latest_patch_num" ]; then
    latest_patch_num=0
fi
next_patch_num=$((latest_patch_num + 1))

for id in "${!commit_groups[@]}"; do
    echo "Processing group for ID $id"
    commit_hashes="${commit_groups[$id]}"
    first_commit_msg="${first_commit_messages[$id]}"

    # Sanitize the commit message for the filename
    sanitized_msg=$(echo "$first_commit_msg" | sed 's/[]//g' | sed 's/[^a-zA-Z0-9._-]/_/g')

    # Construct the patch filename
    patch_filename=$(printf "%04d-%s.patch" "$next_patch_num" "$sanitized_msg")

    # Truncate the filename to 80 characters
    if [ ${#patch_filename} -gt 80 ]; then
        patch_filename="${patch_filename:0:75}_.patch"
    fi
    
    patch_filename_path="$PATCHES_DIR/$patch_filename"
    echo "Creating patch file: $patch_filename"
    # Create/truncate the file
    > "$patch_filename_path"

    # Get the commits for the current ID
    read -r -a commit_array <<< "$commit_hashes"

    # Reverse the array to get chronological order
    commit_array_rev=()
    for i in "${commit_array[@]}"; do
      commit_array_rev=("$i" "${commit_array_rev[@]}")
    done

    # Create a patch for each commit and append it to the file
    for commit_hash in "${commit_array_rev[@]}"; do
        git format-patch -1 "$commit_hash" --stdout >> "$patch_filename_path"
    done

    next_patch_num=$((next_patch_num + 1))
done

echo "Done."


