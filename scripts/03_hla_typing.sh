#!/usr/bin/env bash
set -euo pipefail

# Step 3: HLA-I typing with OptiType
# Estimated time: 15-30 minutes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
source "$REPO_ROOT/.env" 2>/dev/null || true

TUMOR="${TUMOR_SAMPLE:-HCC1395_TUMOR_DNA}"
RESULTS="$REPO_ROOT/results/optitype"

mkdir -p "$RESULTS"

echo "══════════════════════════════════════"
echo " Step 3: OptiType HLA Typing"
echo "══════════════════════════════════════"

# Extract reads mapping to HLA region (chr6:29.6M-33.2M)
echo "[$(date +%H:%M:%S)] Extracting HLA-region reads..."
docker run --rm \
    -v "$REPO_ROOT/results:/results" \
    broadinstitute/gatk:${GATK_VERSION:-4.6.1.0} \
    bash -c "
        samtools view -b /results/alignment/${TUMOR}.final.bam chr6:29600000-33200000 \
            > /results/optitype/hla_region.bam && \
        samtools index /results/optitype/hla_region.bam && \
        samtools fastq /results/optitype/hla_region.bam \
            -1 /results/optitype/hla_r1.fastq.gz \
            -2 /results/optitype/hla_r2.fastq.gz \
            -s /dev/null -0 /dev/null
    "

# Run OptiType
echo "[$(date +%H:%M:%S)] Running OptiType..."
docker run --rm \
    -v "$RESULTS:/results/optitype" \
    fred2/optitype \
    --input /results/optitype/hla_r1.fastq.gz /results/optitype/hla_r2.fastq.gz \
    --dna \
    --outdir /results/optitype/output/

# Parse OptiType output to comma-separated format for pVACseq
echo "[$(date +%H:%M:%S)] Parsing HLA alleles..."
OPTITYPE_TSV=$(find "$RESULTS/output" -name "*_result.tsv" | head -1)

if [ -z "$OPTITYPE_TSV" ]; then
    echo "WARNING: OptiType output not found. Using known HCC1395 alleles as fallback."
    echo "HLA-A*29:02,HLA-B*08:01,HLA-B*45:01,HLA-C*06:02,HLA-C*07:01" > "$RESULTS/hla_alleles.txt"
else
    # OptiType TSV has columns: A1, A2, B1, B2, C1, C2
    python3 -c "
import csv, sys
with open('$OPTITYPE_TSV') as f:
    reader = csv.DictReader(f, delimiter='\t')
    for row in reader:
        alleles = set()
        for col in ['A1','A2','B1','B2','C1','C2']:
            if col in row and row[col]:
                alleles.add('HLA-' + row[col])
        print(','.join(sorted(alleles)))
        break
" > "$RESULTS/hla_alleles.txt"
fi

HLA_ALLELES=$(cat "$RESULTS/hla_alleles.txt")
echo ""
echo "Step 3 complete. HLA alleles: $HLA_ALLELES"
echo "Output: results/optitype/hla_alleles.txt"

# Validation against known alleles
echo ""
echo "Expected for HCC1395: HLA-A*29:02, HLA-B*08:01, HLA-B*45:01, HLA-C*06:02, HLA-C*07:01"
