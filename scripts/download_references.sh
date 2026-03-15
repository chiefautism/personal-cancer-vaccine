#!/usr/bin/env bash
set -euo pipefail

# Download GRCh38 reference genome, GATK resources, and VEP cache
# Total: ~30GB

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
REF="$REPO_ROOT/references"

mkdir -p "$REF/vep_cache"

BROAD="https://storage.googleapis.com/genomics-public-data/resources/broad/hg38/v0"
GATK_BP="https://storage.googleapis.com/gatk-best-practices/somatic-hg38"
ENSEMBL="https://ftp.ensembl.org/pub"

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
    else
        curl -L --progress-bar -o "$dest/$filename" "$url"
    fi
}

echo "============================================"
echo " Downloading GRCh38 references (~30GB)"
echo "============================================"

echo ""
echo "── Reference genome ──"
download "$BROAD/Homo_sapiens_assembly38.fasta" "$REF"
download "$BROAD/Homo_sapiens_assembly38.fasta.fai" "$REF"
download "$BROAD/Homo_sapiens_assembly38.dict" "$REF"

echo ""
echo "── BQSR known sites ──"
download "$BROAD/Homo_sapiens_assembly38.dbsnp138.vcf" "$REF"
download "$BROAD/Homo_sapiens_assembly38.dbsnp138.vcf.idx" "$REF"

echo ""
echo "── Mutect2 resources ──"
download "$GATK_BP/1000g_pon.hg38.vcf.gz" "$REF"
download "$GATK_BP/1000g_pon.hg38.vcf.gz.tbi" "$REF"
download "$GATK_BP/af-only-gnomad.hg38.vcf.gz" "$REF"
download "$GATK_BP/af-only-gnomad.hg38.vcf.gz.tbi" "$REF"

echo ""
echo "── VEP cache (GRCh38, release 113) ──"
download "$ENSEMBL/release-113/variation/vep/homo_sapiens_vep_113_GRCh38.tar.gz" "$REF/vep_cache"
if [ ! -d "$REF/vep_cache/homo_sapiens" ]; then
    echo "  Extracting VEP cache..."
    tar -xzf "$REF/vep_cache/homo_sapiens_vep_113_GRCh38.tar.gz" -C "$REF/vep_cache/"
fi

echo ""
echo "── Protein FASTA (for reference proteome similarity) ──"
download "$ENSEMBL/release-113/fasta/homo_sapiens/pep/Homo_sapiens.GRCh38.pep.all.fa.gz" "$REF"

echo ""
echo "── Building BWA index (takes ~1 hour) ──"
if [ -f "$REF/Homo_sapiens_assembly38.fasta.bwt" ]; then
    echo "  BWA index already exists — skipping"
else
    docker run --rm \
        -v "$REF:/references" \
        biocontainers/bwa:v0.7.17_cv1 \
        bwa index /references/Homo_sapiens_assembly38.fasta
fi

echo ""
echo "Done! References in: $REF/"
du -sh "$REF"
