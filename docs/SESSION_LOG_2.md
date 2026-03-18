# Session Log 2 — March 15-17, 2026

Continuation of the overnight build. Focus: running full pipeline on real patient data, fixing MHCflurry, VEP annotation attempts.

## What Was Accomplished

### MHCflurry Fix (CONFIRMED WORKING)
- Problem: pvactools 6.1.0 installs TF 2.21, MHCflurry 2.0.6 calls `keras.backend.set_session` which was removed in TF 2.16+
- Solution: `pip install tensorflow==2.15.1` BEFORE `pip install pvactools==6.1.0`
- Tested: `mhcflurry-predict --alleles HLA-A0201 --peptides SIINFEKL` returns IC50 = 11,927 nM (correct)
- This means we can now run all 3 algorithms: MHCflurryEL + NetMHCpanEL + BigMHC_EL

### TCR002361 Follicular Lymphoma — Full Pipeline from Raw FASTQ

**Dataset:**
- Patient: TCR002361 from Texas Cancer Research Biobank
- Cancer: Follicular lymphoma (9690/3), lymph node of the groin, 90% cellularity
- SRA Project: PRJNA284596
- Tumor: SRR2089363 (WES, ~12GB FASTQ)
- Normal: SRR2089364 (WES, ~12GB FASTQ)
- Open access, no dbGaP needed

**Steps completed (on Vast.ai Denmark instance #32933987, RTX 5060 Ti, $0.078/hr):**

| Step | Status | Time | Result |
|------|--------|------|--------|
| FASTQ download (ENA FTP) | DONE | 7 min | 14GB, 4 files |
| Reference (Ensembl GRCh38) | DONE | 1 min | 4.4GB |
| BWA index | DONE | 35 min | 2.9GB |
| BWA alignment tumor | DONE | 32 min | 8.4GB BAM, 118.5M reads |
| BWA alignment normal | DONE | 30 min | 8.1GB BAM |
| GATK Mutect2 | DONE | 4 hours | 9,435 PASS variants (9,352 SNV + 83 indel) |
| HLA typing | PLACEHOLDER | - | Using common alleles, needs OptiType |
| VEP annotation | FAILED | multiple attempts | See below |
| pVACseq | NOT STARTED | - | Blocked by VEP |

**VEP annotation attempts (on California instance #32995312, ensembl-vep Docker image):**

1. VEP cache download from Ensembl FTP: too slow (1-3 MB/s, 22GB file, would take 4+ hours)
2. aria2c parallel download: Ensembl FTP throttles per-IP, not per-connection, no speedup
3. VEP --database mode (online, connects to ensembldb.ensembl.org MySQL): works for single variants but hangs/times out on 9435 variants
4. VEP --database without plugins: single variant test CONFIRMED WORKING (connected to homo_sapiens_core_113_38)

**Both instances exited (Vast.ai killed them) before VEP could complete.**

### One-Shot Pipeline Script Created

`scripts/run_tcrb_full.sh` — contains all fixes and runs everything from scratch:
- Uses `ensemblorg/ensembl-vep:release_113.0` as base Docker image (VEP pre-installed)
- Installs Java 17 (GATK 4.6.1.0 requires it)
- Installs TF 2.15.1 before pvactools (MHCflurry fix)
- BigMHC wrapper script (no setup.py in repo)
- aria2c for VEP cache download
- pvacseq install_vep_plugin for Wildtype/Frameshift
- All steps idempotent (check file exists before running)

## All Vast.ai Instances Used

| # | Instance ID | Location | GPU | $/hr | Purpose | Status |
|---|-------------|----------|-----|------|---------|--------|
| 1 | 32872690 | California | RTX 5060 Ti | 0.069 | HCC1395 Easy Mode | destroyed (Docker I/O error) |
| 2 | 32878822 | California | RTX 5060 Ti | 0.069 | HCC1395 Easy Mode retry | destroyed (bad internet) |
| 3 | 32879549 | California | RTX 5080 | 0.116 | HCC1395 pVACseq + ColabFold + LinearDesign | destroyed (8h+ session complete) |
| 4 | 32933987 | Denmark | RTX 5060 Ti | 0.078 | TCRB full pipeline (alignment + Mutect2) | exited (Vast.ai killed) |
| 5 | 32995312 | California | RTX 5060 Ti | 0.069 | VEP annotation (ensembl-vep image) | exited (Vast.ai killed) |

Estimated total Vast.ai spend: ~$3-4 across all instances.

## Issues and Fixes (New)

### Java version for GATK
- Problem: GATK 4.6.1.0 requires Java 17 (class file version 61.0), default apt installs Java 11
- Fix: `apt-get install -y openjdk-17-jre-headless`

### Ensembl reference chromosome naming
- Ensembl GRCh38 uses `1, 2, 3` (not `chr1, chr2, chr3`)
- BWA index + alignment worked fine with Ensembl naming
- Mutect2 worked fine
- VEP --database mode worked fine
- pVACseq should work (it follows VCF contigs)

### VEP cache is 22GB (not 15GB as initially estimated)
- `homo_sapiens_vep_113_GRCh38.tar.gz` is 22GB compressed
- At 1-3 MB/s from Ensembl FTP, download takes 2-6 hours
- aria2c with 16 connections does NOT help (FTP throttles per-IP)
- Alternative: use --database mode (online MySQL), but slow for many variants
- Best approach: use Vast.ai image that already has cache pre-installed, or patient longer download

### Vast.ai instances can die at any time
- Both instances exited without warning after 8-12 hours
- All data lost (no persistent storage)
- Lesson: save results to local machine regularly, or use checkpointing
- The one-shot script (`run_tcrb_full.sh`) is designed to be re-run (idempotent steps)

### fasterq-dump DNS failure
- SRA toolkit fasterq-dump fails on some Vast.ai hosts: `connection not found while validating within network system module`
- Fix: download from ENA FTP instead (`ftp://ftp.sra.ebi.ac.uk/vol1/fastq/...`)
- ENA FTP is fast (14GB in 7 min = ~33 MB/s)

### Google Cloud Storage blocked on some Vast.ai hosts
- `wget https://storage.googleapis.com/...` returns 0 bytes on some hosts
- Fix: use Ensembl FTP mirror instead of GATK Broad resources for reference genome

## What Still Needs To Be Done

### Immediate (to complete TCRB pipeline):
1. Rent fresh Vast.ai instance with `ensemblorg/ensembl-vep:release_113.0` image, 100GB disk
2. Run `scripts/run_tcrb_full.sh` via nohup
3. Monitor progress, download results when complete
4. Expected: ~8-12 hours total, ~$1-2 cost

### For the HCC1395 results already in repo:
1. Re-run pVACseq with MHCflurryEL (now that TF 2.15.1 fix is confirmed) to get IC50 + fold change values
2. This fills in the NA columns in the current results
3. Update visualizations with real IC50 data

### Pipeline improvements:
1. Add checkpointing — save intermediate results to local machine after each step
2. Add RNA-seq integration (STAR + Kallisto)
3. Add Class II predictions
4. Add fusion neoantigen detection (pVACfuse)
5. HLA LOH detection
6. Proper HLA typing for TCRB patient (OptiType or arcasHLA)

## Files Modified/Created This Session

```
scripts/run_tcrb_full.sh              — NEW: one-shot full pipeline for TCRB lymphoma
scripts/run_vastai.sh                 — UPDATED: fixed repo URLs
scripts/utils/visualize_neoantigens.py — UPDATED: fixed repo URLs
docs/TCRB_LYMPHOMA_TODO.md            — UPDATED: added progress table
docs/SESSION_LOG.md                   — existing (session 1)
docs/SESSION_LOG_2.md                 — NEW: this file
README.md                             — UPDATED: multiple additions
```

## How To Continue

```bash
# 1. Rent instance
vastai search offers 'gpu_ram>=16 cpu_ram>=30 cpu_cores>=8 disk_space>=100 dph<=0.20 reliability>0.98 num_gpus=1 rented=False inet_down>=500' --order 'dph' --limit 5
vastai create instance ID --image ensemblorg/ensembl-vep:release_113.0 --disk 100

# 2. Upload script
scp -P PORT scripts/run_tcrb_full.sh root@HOST:/workspace/

# 3. Run
ssh -p PORT root@HOST 'nohup bash /workspace/run_tcrb_full.sh > /tmp/pipeline.log 2>&1 &'

# 4. Monitor
ssh -p PORT root@HOST 'tail -20 /tmp/pipeline.log'

# 5. When done, download results
scp -P PORT root@HOST:/workspace/tcrb/results/*.vcf.gz /Users/adaboost/dev/llm-cure-cancer/results/tcrb/
scp -P PORT root@HOST:/workspace/tcrb/results/pvacseq/MHC_Class_I/*.filtered.tsv /Users/adaboost/dev/llm-cure-cancer/results/tcrb/

# 6. Destroy instance
vastai destroy instance ID
```

## TCRB Dataset Reference

All 7 patients from Texas Cancer Research Biobank (PRJNA284596):

| Case | Cancer | Tumor SRR | Normal SRR | Cellularity |
|------|--------|-----------|------------|-------------|
| TCR000484 | Neuroendocrine carcinoma | SRR2089355 | SRR2089359 | 20% |
| TCR002101 | Pancreatic adenocarcinoma | SRR2089357 | SRR2089356 | 60% |
| TCR002103 | Pancreatic adenocarcinoma | SRR2089360 | SRR2089358 | 20% |
| TCR002201 | Pancreatic adenocarcinoma | SRR2089361 | SRR2089362 | 10% |
| TCR002361 | Follicular lymphoma | SRR2089363 | SRR2089364 | 90% |
| TCR002182 | Pancreatic adenocarcinoma | SRR2089365 | SRR2089366 | 5% |
| TCRBOA6 | Neuroendocrine carcinoma | SRR2184243 | SRR2184242 | 80% |

Source: https://www.nature.com/articles/sdata201610
