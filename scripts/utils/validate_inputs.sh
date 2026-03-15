#!/usr/bin/env bash
set -euo pipefail

# Validate input files before each pipeline stage

MODE="${1:-easy}"
REPO_ROOT="${2:-.}"

ERRORS=0

check_file() {
    local path="$1"
    local desc="$2"
    if [ ! -f "$path" ]; then
        echo "MISSING: $desc ($path)"
        ERRORS=$((ERRORS + 1))
    elif [ ! -s "$path" ]; then
        echo "EMPTY: $desc ($path)"
        ERRORS=$((ERRORS + 1))
    else
        echo "  OK: $desc"
    fi
}

echo "Validating inputs for $MODE mode..."
echo ""

if [ "$MODE" = "easy" ]; then
    INPUTS="$REPO_ROOT/data/easy_mode/HCC1395_inputs"
    check_file "$INPUTS/annotated.expression.vcf.gz" "VEP-annotated VCF"
    check_file "$INPUTS/phased.vcf.gz" "Phased proximal variants VCF"
    check_file "$INPUTS/Homo_sapiens.GRCh38.pep.all.fa.gz" "Reference proteome FASTA"
fi

if [ "$MODE" = "full" ]; then
    check_file "$REPO_ROOT/data/fastq/ERR194146_1.fastq.gz" "Tumor FASTQ R1"
    check_file "$REPO_ROOT/data/fastq/ERR194146_2.fastq.gz" "Tumor FASTQ R2"
    check_file "$REPO_ROOT/data/fastq/ERR194147_1.fastq.gz" "Normal FASTQ R1"
    check_file "$REPO_ROOT/data/fastq/ERR194147_2.fastq.gz" "Normal FASTQ R2"
    check_file "$REPO_ROOT/references/Homo_sapiens_assembly38.fasta" "Reference genome"
    check_file "$REPO_ROOT/references/Homo_sapiens_assembly38.fasta.fai" "Reference index"
    check_file "$REPO_ROOT/references/Homo_sapiens_assembly38.dbsnp138.vcf" "dbSNP"
    check_file "$REPO_ROOT/references/af-only-gnomad.hg38.vcf.gz" "gnomAD"
    check_file "$REPO_ROOT/references/1000g_pon.hg38.vcf.gz" "Panel of normals"
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: $ERRORS file(s) missing or empty."
    if [ "$MODE" = "easy" ]; then
        echo "Run: bash scripts/download_easy_mode_inputs.sh"
    else
        echo "Run: bash scripts/download_demo_data.sh && bash scripts/download_references.sh"
    fi
    exit 1
fi

echo "All inputs validated."
