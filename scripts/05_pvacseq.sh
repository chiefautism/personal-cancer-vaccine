#!/usr/bin/env bash
set -euo pipefail

# Step 5: pVACseq neoantigen prediction
# Estimated time: 30-90 minutes depending on algorithms

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
source "$REPO_ROOT/.env" 2>/dev/null || true

PVAC_IMG="griffithlab/pvactools:${PVACTOOLS_VERSION:-6.1.0}"
TUMOR="${TUMOR_SAMPLE:-HCC1395_TUMOR_DNA}"
NORMAL="${NORMAL_SAMPLE:-HCC1395_NORMAL_DNA}"
THREADS="${THREADS:-4}"
MODE="${1:-full}"

RESULTS="$REPO_ROOT/results/pvacseq"
mkdir -p "$RESULTS"

echo "══════════════════════════════════════"
echo " Step 5: pVACseq Neoantigen Prediction"
echo "══════════════════════════════════════"

# Determine input VCF and HLA alleles based on mode
if [ "$MODE" = "easy" ]; then
    INPUT_VCF="/data/easy_mode/HCC1395_inputs/annotated.expression.vcf.gz"
    PHASED_VCF="--phased-proximal-variants-vcf /data/easy_mode/HCC1395_inputs/phased.vcf.gz"
    PROTEIN_FASTA="/data/easy_mode/HCC1395_inputs/Homo_sapiens.GRCh38.pep.all.fa.gz"
    HLA_ALLELES="HLA-A*29:02,HLA-B*08:01,HLA-B*45:01,HLA-C*06:02,HLA-C*07:01"
else
    INPUT_VCF="/results/vep/annotated.vcf.gz"
    PHASED_VCF=""
    PROTEIN_FASTA="/references/Homo_sapiens.GRCh38.pep.all.fa.gz"
    # Read HLA alleles from OptiType output or fall back to config
    if [ -f "$REPO_ROOT/results/optitype/hla_alleles.txt" ]; then
        HLA_ALLELES=$(cat "$REPO_ROOT/results/optitype/hla_alleles.txt")
    else
        HLA_ALLELES="HLA-A*29:02,HLA-B*08:01,HLA-B*45:01,HLA-C*06:02,HLA-C*07:01"
        echo "WARNING: Using known HCC1395 HLA alleles (OptiType output not found)"
    fi
fi

echo "Mode:        $MODE"
echo "Input VCF:   $INPUT_VCF"
echo "HLA alleles: $HLA_ALLELES"
echo ""

echo "[$(date +%H:%M:%S)] Running pVACseq..."
docker run --rm \
    -v "$REPO_ROOT/data:/data" \
    -v "$REPO_ROOT/results:/results" \
    -v "$REPO_ROOT/references:/references" \
    -v "$REPO_ROOT/config:/config" \
    "$PVAC_IMG" \
    pvacseq run \
    "$INPUT_VCF" \
    "$TUMOR" \
    "$HLA_ALLELES" \
    MHCflurryEL NetMHCpanEL BigMHC_EL \
    /results/pvacseq \
    --normal-sample-name "$NORMAL" \
    $PHASED_VCF \
    --iedb-install-directory /opt/iedb \
    --pass-only \
    --allele-specific-binding-thresholds \
    --percentile-threshold "${PERCENTILE_THRESHOLD:-2}" \
    --run-reference-proteome-similarity \
    --peptide-fasta "$PROTEIN_FASTA" \
    --problematic-amino-acids C \
    -e1 "${EPITOPE_LENGTHS:-8,9,10,11}" \
    --n-threads "$THREADS" \
    --keep-tmp-files

echo ""
echo "Step 5 complete."
echo "Output: results/pvacseq/MHC_Class_I/${TUMOR}.filtered.tsv"
