# TCR002361 Follicular Lymphoma — Full Pipeline Run (In Progress)

## Dataset

- **Patient:** TCR002361 from Texas Cancer Research Biobank
- **Cancer:** Follicular lymphoma (9690/3), lymph node of the groin
- **Cellularity:** 90% (highest in TCRB dataset — cleanest signal)
- **Sex:** Available in SRA metadata
- **Sequencing:** Whole Exome Sequencing (WES), ~200x coverage
- **SRA Project:** PRJNA284596

## SRA Accessions

| Sample | SRR | Type | Size |
|--------|-----|------|------|
| TCR002361-T | SRR2089363 | Tumor (lymph node) | ~12GB |
| TCR002361-N | SRR2089364 | Normal (blood) | ~12GB |

## Download Commands

SRA toolkit fasterq-dump failed on Vast.ai due to DNS issues. Use ENA FTP instead:

```bash
# Get ENA URLs first
curl -s "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=SRR2089363&result=read_run&fields=fastq_ftp&format=tsv"
curl -s "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=SRR2089364&result=read_run&fields=fastq_ftp&format=tsv"

# Or try direct wget from ENA
wget ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR208/003/SRR2089363/SRR2089363_1.fastq.gz
wget ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR208/003/SRR2089363/SRR2089363_2.fastq.gz
wget ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR208/004/SRR2089364/SRR2089364_1.fastq.gz
wget ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR208/004/SRR2089364/SRR2089364_2.fastq.gz
```

## Full Pipeline Steps

This is the FULL pipeline from raw FASTQ — no pre-processed data:

1. Download FASTQ (tumor + normal) — ~24GB
2. Download GRCh38 reference + GATK resources — ~30GB
3. BWA-MEM alignment (tumor + normal) — ~4-6h for WES
4. GATK MarkDuplicates + BQSR
5. GATK Mutect2 tumor-normal — ~2-3h for WES
6. OptiType HLA typing — ~15 min
7. VEP annotation — ~30 min
8. pVACseq neoantigen prediction — ~45 min
9. ColabFold structure prediction — ~3h
10. LinearDesign mRNA optimization — ~1 min
11. Construct assembly — instant

## Estimated Resources

- Disk: ~80GB (FASTQ + reference + results)
- RAM: 16GB minimum for WES (vs 32GB for WGS)
- Time: ~12-16 hours total
- Cost: ~$1.50-2.00 on Vast.ai at $0.12/hr

## Current Progress (Vast.ai Instance #32933987, Denmark)

| Step | Status | Time | Result |
|------|--------|------|--------|
| FASTQ download | DONE | 7 min | 14GB (4 files from ENA FTP) |
| Reference download | DONE | 1 min | 4.4GB (Ensembl GRCh38) |
| BWA index | DONE | 35 min | 2.9GB index |
| BWA alignment (tumor) | DONE | 32 min | 8.4GB BAM, 118.5M reads |
| BWA alignment (normal) | DONE | 30 min | 8.1GB BAM |
| GATK Mutect2 | DONE | 4h | **9,435 PASS variants** (29,043 total, 9,352 SNV + 83 indel) |
| HLA typing | PLACEHOLDER | - | Using common alleles, need OptiType |
| VEP annotation | BLOCKED | - | Perl VEP needs Bio::EnsEMBL (Docker easiest) |
| pVACseq | WAITING | - | Needs VEP-annotated VCF |
| MHCflurry | FIXED | - | TF 2.15.1 downgrade works |

### Blockers

**VEP annotation** is the only remaining blocker. Options:
1. Use Docker: `docker run ensemblorg/ensembl-vep:release_113.0 vep ...` (needs Docker on host)
2. Fresh instance with Docker support (not all Vast.ai hosts have Docker-in-Docker)
3. Use Ensembl VEP web tool (upload VCF, max 50MB, our file is 2.6MB compressed -- fits)
4. Install VEP via full perl INSTALL.pl with --AUTO acfp (downloads all deps + cache, ~15GB)

### What Went Wrong

- fasterq-dump failed with DNS error on first instance
- First Vast.ai instance had 0 MB/s GitHub download speed
- GATK 4.6.1.0 requires Java 17 (apt default was Java 11)
- Ensembl reference uses chr names 1,2,3 not chr1,chr2,chr3
- conda install ensembl-vep hangs for 1+ hour solving environment
- VEP perl install needs Bio::EnsEMBL::Registry (full Ensembl API)
- SSH unstable on overloaded hosts (load avg 48)
- MHCflurry fixed by pinning TF 2.15.1

## All TCRB Patients Available

| Case | Cancer | Tumor | Normal | Cellularity |
|------|--------|-------|--------|-------------|
| TCR000484 | Neuroendocrine carcinoma | SRR2089355 | SRR2089359 | 20% |
| TCR002101 | Pancreatic adenocarcinoma | SRR2089357 | SRR2089356 | 60% |
| TCR002103 | Pancreatic adenocarcinoma | SRR2089360 | SRR2089358 | 20% |
| TCR002201 | Pancreatic adenocarcinoma | SRR2089361 | SRR2089362 | 10% |
| **TCR002361** | **Follicular lymphoma** | **SRR2089363** | **SRR2089364** | **90%** |
| TCR002182 | Pancreatic adenocarcinoma | SRR2089365 | SRR2089366 | 5% |
| TCRBOA6 | Neuroendocrine carcinoma | SRR2184243 | SRR2184242 | 80% |

Source: [Texas Cancer Research Biobank — Nature Scientific Data](https://www.nature.com/articles/sdata201610), SRA: [PRJNA284596](https://www.ncbi.nlm.nih.gov/sra/?term=PRJNA284596)
