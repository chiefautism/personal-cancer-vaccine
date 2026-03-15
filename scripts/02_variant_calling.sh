#!/usr/bin/env bash
set -euo pipefail

# Step 2: GATK Mutect2 somatic variant calling
# Estimated time: 4-6 hours for WGS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
source "$REPO_ROOT/.env" 2>/dev/null || true

TUMOR="${TUMOR_SAMPLE:-HCC1395_TUMOR_DNA}"
NORMAL="${NORMAL_SAMPLE:-HCC1395_NORMAL_DNA}"
GATK_IMG="broadinstitute/gatk:${GATK_VERSION:-4.6.1.0}"
REF="/references/Homo_sapiens_assembly38.fasta"
RESULTS="/results/variant_calling"

mkdir -p "$REPO_ROOT/results/variant_calling"

run_gatk() {
    docker run --rm \
        -v "$REPO_ROOT/results:/results" \
        -v "$REPO_ROOT/references:/references" \
        "$GATK_IMG" \
        gatk "$@"
}

echo "══════════════════════════════════════"
echo " Step 2: Mutect2 Variant Calling"
echo "══════════════════════════════════════"

# Mutect2 tumor-normal mode
echo "[$(date +%H:%M:%S)] Running Mutect2..."
run_gatk Mutect2 \
    -R $REF \
    -I /results/alignment/${TUMOR}.final.bam \
    -tumor "$TUMOR" \
    -I /results/alignment/${NORMAL}.final.bam \
    -normal "$NORMAL" \
    --germline-resource /references/af-only-gnomad.hg38.vcf.gz \
    --panel-of-normals /references/1000g_pon.hg38.vcf.gz \
    --f1r2-tar-gz $RESULTS/f1r2.tar.gz \
    -O $RESULTS/mutect2_unfiltered.vcf.gz

# Learn read orientation model (for filtering)
echo "[$(date +%H:%M:%S)] Learning orientation model..."
run_gatk LearnReadOrientationModel \
    -I $RESULTS/f1r2.tar.gz \
    -O $RESULTS/read-orientation-model.tar.gz

# Pileup summaries for contamination estimation
echo "[$(date +%H:%M:%S)] Estimating contamination..."
run_gatk GetPileupSummaries \
    -I /results/alignment/${TUMOR}.final.bam \
    -V /references/af-only-gnomad.hg38.vcf.gz \
    -L /references/af-only-gnomad.hg38.vcf.gz \
    -O $RESULTS/tumor_pileups.table

run_gatk GetPileupSummaries \
    -I /results/alignment/${NORMAL}.final.bam \
    -V /references/af-only-gnomad.hg38.vcf.gz \
    -L /references/af-only-gnomad.hg38.vcf.gz \
    -O $RESULTS/normal_pileups.table

run_gatk CalculateContamination \
    -I $RESULTS/tumor_pileups.table \
    -matched $RESULTS/normal_pileups.table \
    -O $RESULTS/contamination.table \
    --tumor-segmentation $RESULTS/segments.table

# Filter variants
echo "[$(date +%H:%M:%S)] Filtering variants..."
run_gatk FilterMutectCalls \
    -R $REF \
    -V $RESULTS/mutect2_unfiltered.vcf.gz \
    --contamination-table $RESULTS/contamination.table \
    --tumor-segmentation $RESULTS/segments.table \
    --ob-priors $RESULTS/read-orientation-model.tar.gz \
    -O $RESULTS/mutect2_filtered.vcf.gz

# Count PASS variants
PASS_COUNT=$(docker run --rm \
    -v "$REPO_ROOT/results:/results" \
    "$GATK_IMG" \
    bash -c "zgrep -c '^[^#].*PASS' $RESULTS/mutect2_filtered.vcf.gz || echo 0")

echo ""
echo "Step 2 complete. $PASS_COUNT PASS variants."
echo "Output: results/variant_calling/mutect2_filtered.vcf.gz"
