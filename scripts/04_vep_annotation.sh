#!/usr/bin/env bash
set -euo pipefail

# Step 4: VEP annotation with Frameshift + Wildtype plugins (required by pVACseq)
# Estimated time: 30-60 minutes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
source "$REPO_ROOT/.env" 2>/dev/null || true

VEP_IMG="ensemblorg/ensembl-vep:release_${VEP_VERSION:-113}.0"
INPUT_VCF="/results/variant_calling/mutect2_filtered.vcf.gz"
OUTPUT_VCF="/results/vep/annotated.vcf"
RESULTS="$REPO_ROOT/results/vep"

mkdir -p "$RESULTS"

echo "══════════════════════════════════════"
echo " Step 4: VEP Annotation"
echo "══════════════════════════════════════"

echo "[$(date +%H:%M:%S)] Running VEP with Frameshift + Wildtype plugins..."
docker run --rm \
    -v "$REPO_ROOT/results:/results" \
    -v "$REPO_ROOT/references:/references" \
    "$VEP_IMG" \
    vep \
    --input_file "$INPUT_VCF" \
    --output_file "$OUTPUT_VCF" \
    --format vcf \
    --vcf \
    --symbol \
    --terms SO \
    --tsl \
    --mane_select \
    --canonical \
    --biotype \
    --hgvs \
    --fasta /references/Homo_sapiens_assembly38.fasta \
    --offline \
    --cache \
    --dir_cache /references/vep_cache/ \
    --plugin Frameshift \
    --plugin Wildtype \
    --pick \
    --transcript_version \
    --force_overwrite

# Compress and index for pVACseq
echo "[$(date +%H:%M:%S)] Compressing and indexing..."
docker run --rm \
    -v "$REPO_ROOT/results:/results" \
    "$VEP_IMG" \
    bash -c "
        bgzip -f /results/vep/annotated.vcf && \
        tabix -p vcf /results/vep/annotated.vcf.gz
    "

echo ""
echo "Step 4 complete."
echo "Output: results/vep/annotated.vcf.gz"
