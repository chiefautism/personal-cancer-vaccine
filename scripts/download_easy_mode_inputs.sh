#!/usr/bin/env bash
set -euo pipefail

# Download pre-processed HCC1395 inputs for Easy Mode (~200MB)
# Source: griffithlab pVACtools Intro Course

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DEST="$REPO_ROOT/data/easy_mode"

mkdir -p "$DEST"

URL="https://raw.githubusercontent.com/griffithlab/pVACtools_Intro_Course/main/HCC1395_inputs.zip"

echo "============================================"
echo " Downloading Easy Mode inputs (~200MB)"
echo "============================================"

if [ -d "$DEST/HCC1395_inputs" ] && [ -f "$DEST/HCC1395_inputs/annotated.expression.vcf.gz" ]; then
    echo "Easy Mode inputs already downloaded. Skipping."
    exit 0
fi

if command -v wget &>/dev/null; then
    wget -q --show-progress -O "$DEST/HCC1395_inputs.zip" "$URL"
elif command -v curl &>/dev/null; then
    curl -L --progress-bar -o "$DEST/HCC1395_inputs.zip" "$URL"
else
    echo "ERROR: wget or curl required" >&2
    exit 1
fi

echo "Extracting..."
unzip -qo "$DEST/HCC1395_inputs.zip" -d "$DEST/"
rm -f "$DEST/HCC1395_inputs.zip"

echo ""
echo "Done! Files in: $DEST/HCC1395_inputs/"
ls -lh "$DEST/HCC1395_inputs/"
