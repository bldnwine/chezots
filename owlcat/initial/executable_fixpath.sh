#!/usr/bin/env bash
CHEZMOI_DIR="${HOME}/.local/share/chezmoi"

if [ ! -d "$CHEZMOI_DIR" ]; then
    echo "chezmoi source dir not found at $CHEZMOI_DIR" >&2
    exit 1
fi

TARGET_USER_HOME="$HOME"
SOURCE_USER="/home/bldnwine"

if [ "$TARGET_USER_HOME" = "$SOURCE_USER" ]; then
    echo "Already on bldnwine's account, nothing to fix."
    exit 0
fi

count=0
while IFS= read -r -d '' file; do
    if grep -q "$SOURCE_USER" "$file" 2>/dev/null; then
        sed -i "s|$SOURCE_USER|$TARGET_USER_HOME|g" "$file"
        count=$((count + 1))
    fi
done < <(find "$TARGET_USER_HOME/.config" "$TARGET_USER_HOME/.local/bin" -type f -print0 2>/dev/null)

echo "Fixed $count files."
