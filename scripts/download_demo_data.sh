#!/usr/bin/env bash
set -euo pipefail

# Download raw FASTQ files for Full Mode
# HCC1395 (tumor) + HCC1395BL (matched normal) from ENA
# WARNING: ~40GB total download for WGS data

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DEST="$REPO_ROOT/data/fastq"

mkdir -p "$DEST"

echo "============================================"
echo " Downloading Full Mode FASTQ data (~40GB)"
echo " This will take a while..."
echo "============================================"

# ENA FTP base
ENA="ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR194"

download() {
    local url="$1"
    local dest="$2"
    local filename
    filename=$(basename "$url")

    if [ -f "$dest/$filename" ]; then
        echo "  Already exists: $filename — skipping"
        return 0
    fi

    echo "  Downloading: $filename"
    if command -v wget &>/dev/null; then
        wget -q --show-progress -P "$dest" "$url"
    elif command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$dest/$filename" "$url"
    else
        echo "ERROR: wget or curl required" >&2
        exit 1
    fi
}

echo ""
echo "── Tumor: HCC1395 (ERR194146) ──"
download "${ENA}/ERR194146/ERR194146_1.fastq.gz" "$DEST"
download "${ENA}/ERR194146/ERR194146_2.fastq.gz" "$DEST"

echo ""
echo "── Normal: HCC1395BL (ERR194147) ──"
download "${ENA}/ERR194147/ERR194147_1.fastq.gz" "$DEST"
download "${ENA}/ERR194147/ERR194147_2.fastq.gz" "$DEST"

echo ""
echo "Done! FASTQ files in: $DEST/"
ls -lh "$DEST/"
