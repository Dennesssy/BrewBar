#!/bin/bash
HEADER="// Copyright © 2026 Dennis Stewart. All rights reserved."

find . -name "*.swift" -type f | while read -r file; do
    # Check if header already exists
    if ! head -n 1 "$file" | grep -q "Dennis Stewart"; then
        # Create a temporary file
        tmp=$(mktemp)
        echo "$HEADER" > "$tmp"
        echo "" >> "$tmp"
        cat "$file" >> "$tmp"
        mv "$tmp" "$file"
    fi
done
