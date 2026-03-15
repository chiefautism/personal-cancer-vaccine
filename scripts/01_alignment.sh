#!/usr/bin/env bash
set -euo pipefail

# Step 1: BWA-MEM alignment + MarkDuplicates + BQSR
# Estimated time: 8-10 hours for WGS at 4 threads

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
source "$REPO_ROOT/.env" 2>/dev/null || true

THREADS="${THREADS:-4}"
REF="/references/Homo_sapiens_assembly38.fasta"
DBSNP="/references/Homo_sapiens_assembly38.dbsnp138.vcf"
RESULTS="/results/alignment"

mkdir -p "$RESULTS"

align_sample() {
    local SAMPLE="$1"
    local R1="$2"
    local R2="$3"

    echo ""
    echo "══════════════════════════════════════"
    echo " Aligning: $SAMPLE"
    echo "══════════════════════════════════════"

    # BWA-MEM alignment
    echo "[$(date +%H:%M:%S)] Running BWA-MEM..."
    docker run --rm \
        -v "$REPO_ROOT/data:/data" \
        -v "$REPO_ROOT/references:/references" \
        -v "$REPO_ROOT/results:/results" \
        biocontainers/bwa:v0.7.17_cv1 \
        bash -c "bwa mem -t $THREADS \
            -R '@RG\tID:${SAMPLE}\tSM:${SAMPLE}\tPL:ILLUMINA\tLB:lib1' \
            $REF $R1 $R2 | \
            samtools sort -@$THREADS -o /results/alignment/${SAMPLE}.sorted.bam && \
            samtools index /results/alignment/${SAMPLE}.sorted.bam"

    # Mark Duplicates
    echo "[$(date +%H:%M:%S)] Marking duplicates..."
    docker run --rm \
        -v "$REPO_ROOT/results:/results" \
        -v "$REPO_ROOT/references:/references" \
        broadinstitute/gatk:${GATK_VERSION:-4.6.1.0} \
        gatk MarkDuplicates \
            -I /results/alignment/${SAMPLE}.sorted.bam \
            -O /results/alignment/${SAMPLE}.dedup.bam \
            -M /results/alignment/${SAMPLE}.dedup_metrics.txt \
            --CREATE_INDEX true

    # Base Quality Score Recalibration
    echo "[$(date +%H:%M:%S)] Running BQSR..."
    docker run --rm \
        -v "$REPO_ROOT/results:/results" \
        -v "$REPO_ROOT/references:/references" \
        broadinstitute/gatk:${GATK_VERSION:-4.6.1.0} \
        gatk BaseRecalibrator \
            -I /results/alignment/${SAMPLE}.dedup.bam \
            -R $REF \
            --known-sites $DBSNP \
            -O /results/alignment/${SAMPLE}.recal_table

    docker run --rm \
        -v "$REPO_ROOT/results:/results" \
        -v "$REPO_ROOT/references:/references" \
        broadinstitute/gatk:${GATK_VERSION:-4.6.1.0} \
        gatk ApplyBQSR \
            -I /results/alignment/${SAMPLE}.dedup.bam \
            -R $REF \
            --bqsr-recal-file /results/alignment/${SAMPLE}.recal_table \
            -O /results/alignment/${SAMPLE}.final.bam

    echo "[$(date +%H:%M:%S)] Done: $SAMPLE"
}

TUMOR="${TUMOR_SAMPLE:-HCC1395_TUMOR_DNA}"
NORMAL="${NORMAL_SAMPLE:-HCC1395_NORMAL_DNA}"

align_sample "$TUMOR" \
    "/data/fastq/ERR194146_1.fastq.gz" \
    "/data/fastq/ERR194146_2.fastq.gz"

align_sample "$NORMAL" \
    "/data/fastq/ERR194147_1.fastq.gz" \
    "/data/fastq/ERR194147_2.fastq.gz"

echo ""
echo "Step 1 complete. BAMs in: results/alignment/"
ls -lh "$REPO_ROOT/results/alignment/"*.final.bam 2>/dev/null || true
