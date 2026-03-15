# Troubleshooting

## Docker Issues

### "Cannot connect to the Docker daemon"
Start Docker Desktop. On macOS: open Docker.app and wait for it to fully start.

### Out of memory during alignment or variant calling
Increase Docker memory limit: Docker Desktop → Settings → Resources → Memory → set to 16GB+ (Easy Mode) or 32GB+ (Full Mode).

### ARM Mac (M1/M2/M3) — image platform mismatch
All images are linux/amd64. Docker Desktop handles emulation automatically. If you see warnings about platform mismatch, they're safe to ignore.

### "No space left on device"
Full Mode needs ~100GB free. Delete intermediate files:
```bash
rm -f results/alignment/*.sorted.bam results/alignment/*.dedup.bam
```

## pVACseq Issues

### "No epitopes found"
1. Check your VCF has PASS variants: `zgrep -c PASS results/variant_calling/mutect2_filtered.vcf.gz`
2. Verify VEP annotation includes Frameshift and Wildtype plugin output
3. Check HLA allele format: must be `HLA-A*29:02` not `A*29:02` or `HLA-A29:02`

### pVACseq runs but output TSV is empty
- Try lowering `--percentile-threshold` to 5 or removing it
- Remove `--pass-only` to include non-PASS variants
- Add more prediction algorithms: `all_class_i`

## VEP Issues

### VEP cache download fails
Try the mirror: `https://ftp.ensembl.org/pub/release-113/variation/vep/homo_sapiens_vep_113_GRCh38.tar.gz`

If mirrors are down, use `--cache_version 112` with release_112 cache instead.

### VEP "Plugin Wildtype not found"
The Wildtype and Frameshift plugins must be installed. With the official Docker image they should be pre-installed. If not:
```bash
docker run -it ensemblorg/ensembl-vep:release_113.0 \
  perl INSTALL.pl --AUTO p --PLUGINS Wildtype,Frameshift
```

## Download Issues

### ENA FASTQ download is slow
Use Aspera for faster downloads (requires aspera client):
```bash
ascp -QT -l 300m -P33001 era-fasp@fasp.sra.ebi.ac.uk:/vol1/fastq/ERR194/ERR194146/ERR194146_1.fastq.gz data/fastq/
```

### griffithlab Easy Mode ZIP download fails
Try the direct GitHub release URL or clone the repo:
```bash
git clone https://github.com/griffithlab/pVACtools_Intro_Course.git data/easy_mode/pVACtools_course
cp -r data/easy_mode/pVACtools_course/HCC1395_inputs data/easy_mode/
```

## General

### Pipeline fails mid-way and I want to resume
Use `--skip-to N` to skip completed steps:
```bash
bash scripts/run_pipeline.sh --mode full --skip-to 4  # Resume from VEP
```

### How do I use my own tumor/normal data?
Edit `.env` and `config/pipeline_config.yaml` with your sample names, FASTQ paths, and HLA alleles. The pipeline structure is the same for any tumor/normal pair on GRCh38.

### Can I use this for a non-human genome?
Not directly. The pipeline is built for GRCh38. For canine (dog) genomes, you'd need:
- CanFam4 reference genome
- Dog-specific VEP cache
- Dog MHC (DLA) allele support in the prediction step
This is tracked as a future TODO.
