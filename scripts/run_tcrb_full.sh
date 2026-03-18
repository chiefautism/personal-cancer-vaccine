#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Full pipeline: TCR002361 Follicular Lymphoma (Texas Cancer Research Biobank)
# Run on Vast.ai with ensemblorg/ensembl-vep:release_113.0 image
#
# Usage:
#   vastai create instance ID --image ensemblorg/ensembl-vep:release_113.0 --disk 100
#   scp this script to instance
#   nohup bash run_tcrb_full.sh > /tmp/pipeline.log 2>&1 &
#
# Estimated time: 8-12 hours
# Estimated cost: ~$1-2 at $0.07-0.12/hr
# =============================================================================

LOG=/tmp/tcrb_pipeline.log
exec > >(tee -a $LOG) 2>&1

export MKL_THREADING_LAYER=GNU
export CUDA_VISIBLE_DEVICES=""

WORKDIR=/workspace/tcrb
mkdir -p $WORKDIR/{fastq,references,results}
cd $WORKDIR

echo "[$(date +%H:%M:%S)] === TCR002361 FOLLICULAR LYMPHOMA — FULL PIPELINE ==="

# ─── STEP 0: INSTALL DEPENDENCIES ───
echo "[$(date +%H:%M:%S)] STEP 0: Installing dependencies"
apt-get update -qq
apt-get install -y -qq bwa samtools tabix unzip gcc g++ python3-dev python3-pip \
  zlib1g-dev libbz2-dev liblzma-dev openjdk-17-jre-headless 2>/dev/null

pip install tensorflow==2.15.1 2>&1 | tail -3
pip install pvactools==6.1.0 mhcflurry==2.0.6 matplotlib seaborn 2>&1 | tail -3
mhcflurry-downloads fetch models_class1_presentation 2>&1 | tail -3

# BigMHC
if [ ! -d /opt/bigmhc ]; then
  git clone --depth 1 https://github.com/KarchinLab/bigmhc.git /opt/bigmhc 2>&1 | tail -3
  echo '#!/bin/bash' > /usr/local/bin/bigmhc_predict
  echo 'python3 /opt/bigmhc/src/predict.py "$@"' >> /usr/local/bin/bigmhc_predict
  chmod +x /usr/local/bin/bigmhc_predict
fi

# GATK
if ! which gatk 2>/dev/null; then
  wget -q https://github.com/broadinstitute/gatk/releases/download/4.6.1.0/gatk-4.6.1.0.zip -O /tmp/gatk.zip
  unzip -qo /tmp/gatk.zip -d /opt/
  ln -sf /opt/gatk-4.6.1.0/gatk /usr/local/bin/gatk
  rm /tmp/gatk.zip
fi

# VEP plugins (Wildtype + Frameshift)
vep_plugins_dir=$(vep --dir_plugins 2>/dev/null | grep -oP '/.*plugins' || echo "/opt/vep/Plugins")
pvacseq install_vep_plugin "$vep_plugins_dir" 2>/dev/null || true

echo "[$(date +%H:%M:%S)] STEP 0 DONE"

# ─── STEP 1: DOWNLOAD FASTQ ───
echo "[$(date +%H:%M:%S)] STEP 1: FASTQ download"
cd $WORKDIR/fastq
ENA="ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR208"
for f in 003/SRR2089363/SRR2089363_1.fastq.gz 003/SRR2089363/SRR2089363_2.fastq.gz \
         004/SRR2089364/SRR2089364_1.fastq.gz 004/SRR2089364/SRR2089364_2.fastq.gz; do
  fname=$(basename $f)
  [ -f "$fname" ] && [ $(stat -c%s "$fname" 2>/dev/null || echo 0) -gt 1000000 ] && \
    echo "  Have $fname" || { echo "  Downloading $fname"; wget -q -c "${ENA}/${f}"; }
done
echo "[$(date +%H:%M:%S)] STEP 1 DONE"
ls -lh .

# ─── STEP 2: DOWNLOAD REFERENCE ───
echo "[$(date +%H:%M:%S)] STEP 2: Reference genome"
cd $WORKDIR/references
if [ ! -f GRCh38.fa ]; then
  wget -q https://ftp.ensembl.org/pub/release-113/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz -O GRCh38.fa.gz
  gunzip GRCh38.fa.gz
  samtools faidx GRCh38.fa
  samtools dict GRCh38.fa > GRCh38.dict
fi
echo "[$(date +%H:%M:%S)] STEP 2 DONE"

# ─── STEP 3: BWA ALIGNMENT ───
echo "[$(date +%H:%M:%S)] STEP 3: BWA alignment"
cd $WORKDIR
REF=references/GRCh38.fa
[ -f ${REF}.bwt ] || { echo "  Building BWA index..."; bwa index $REF; }
[ -f results/tumor.sorted.bam ] || {
  echo "  Aligning tumor..."
  bwa mem -t 16 -R "@RG\tID:TUMOR\tSM:TUMOR\tPL:ILLUMINA" $REF \
    fastq/SRR2089363_1.fastq.gz fastq/SRR2089363_2.fastq.gz 2>/dev/null | \
    samtools sort -@4 -o results/tumor.sorted.bam
  samtools index results/tumor.sorted.bam
}
[ -f results/normal.sorted.bam ] || {
  echo "  Aligning normal..."
  bwa mem -t 16 -R "@RG\tID:NORMAL\tSM:NORMAL\tPL:ILLUMINA" $REF \
    fastq/SRR2089364_1.fastq.gz fastq/SRR2089364_2.fastq.gz 2>/dev/null | \
    samtools sort -@4 -o results/normal.sorted.bam
  samtools index results/normal.sorted.bam
}
echo "[$(date +%H:%M:%S)] STEP 3 DONE"

# ─── STEP 4: MUTECT2 ───
echo "[$(date +%H:%M:%S)] STEP 4: Mutect2"
cd $WORKDIR
if [ ! -f results/mutect2.filtered.vcf.gz ]; then
  gatk Mutect2 -R $REF \
    -I results/tumor.sorted.bam -tumor TUMOR \
    -I results/normal.sorted.bam -normal NORMAL \
    -O results/mutect2.unfiltered.vcf.gz \
    --native-pair-hmm-threads 16 2>&1

  gatk FilterMutectCalls -R $REF \
    -V results/mutect2.unfiltered.vcf.gz \
    -O results/mutect2.filtered.vcf.gz 2>&1
fi
PASS=$(zgrep -v '^#' results/mutect2.filtered.vcf.gz | grep -cw PASS || echo 0)
echo "[$(date +%H:%M:%S)] STEP 4 DONE: $PASS PASS variants"

# ─── STEP 5: VEP ANNOTATION ───
echo "[$(date +%H:%M:%S)] STEP 5: VEP annotation"
cd $WORKDIR

# Install VEP cache
if [ ! -d /opt/vep/.vep/homo_sapiens ]; then
  echo "  Downloading VEP cache..."
  cd /opt/vep/.vep
  apt-get install -y -qq aria2 2>/dev/null
  aria2c -x 16 -s 16 --file-allocation=none \
    "https://ftp.ensembl.org/pub/release-113/variation/vep/homo_sapiens_vep_113_GRCh38.tar.gz" 2>&1 || \
  wget "https://ftp.ensembl.org/pub/release-113/variation/vep/homo_sapiens_vep_113_GRCh38.tar.gz" 2>&1
  tar xzf homo_sapiens_vep_113_GRCh38.tar.gz
  rm -f homo_sapiens_vep_113_GRCh38.tar.gz
  cd $WORKDIR
fi

# Extract PASS-only VCF
zgrep "^#" results/mutect2.filtered.vcf.gz > results/pass_only.vcf
zgrep -v "^#" results/mutect2.filtered.vcf.gz | grep -w PASS >> results/pass_only.vcf

vep \
  --input_file results/pass_only.vcf \
  --output_file results/vep_annotated.vcf \
  --format vcf --vcf --symbol --terms SO --tsl \
  --mane_select --canonical --biotype --hgvs \
  --fasta $REF \
  --offline --cache --dir_cache /opt/vep/.vep \
  --plugin Frameshift --plugin Wildtype \
  --pick --transcript_version \
  --force_overwrite 2>&1

bgzip -c results/vep_annotated.vcf > results/vep_annotated.vcf.gz
tabix -p vcf results/vep_annotated.vcf.gz
VEP_COUNT=$(grep -vc '^#' results/vep_annotated.vcf || echo 0)
echo "[$(date +%H:%M:%S)] STEP 5 DONE: $VEP_COUNT annotated variants"

# ─── STEP 6: HLA TYPING ───
echo "[$(date +%H:%M:%S)] STEP 6: HLA typing"
# Placeholder -- OptiType hard to install without Docker
# Using common Caucasian HLA alleles
echo "HLA-A*02:01,HLA-A*03:01,HLA-B*07:02,HLA-B*44:02,HLA-C*05:01,HLA-C*07:02" > results/hla_alleles.txt
HLA=$(cat results/hla_alleles.txt)
echo "  HLA: $HLA (placeholder -- needs OptiType for real typing)"
echo "[$(date +%H:%M:%S)] STEP 6 DONE"

# ─── STEP 7: PVACSEQ ───
echo "[$(date +%H:%M:%S)] STEP 7: pVACseq neoantigen prediction"
mkdir -p results/pvacseq
pvacseq run \
  results/vep_annotated.vcf.gz \
  TUMOR \
  "$HLA" \
  MHCflurryEL NetMHCpanEL BigMHC_EL \
  results/pvacseq \
  --normal-sample-name NORMAL \
  --pass-only \
  --allele-specific-binding-thresholds \
  --percentile-threshold 2 \
  -e1 8,9,10,11 \
  --n-threads 14 2>&1

echo "[$(date +%H:%M:%S)] STEP 7 DONE"
ls -lh results/pvacseq/MHC_Class_I/*.filtered.tsv 2>/dev/null || echo "Check results/pvacseq/"

echo ""
echo "[$(date +%H:%M:%S)] === PIPELINE COMPLETE ==="
echo "Files:"
ls -lh results/*.vcf.gz results/*.bam results/pvacseq/MHC_Class_I/*.tsv 2>/dev/null
df -h / | tail -1
