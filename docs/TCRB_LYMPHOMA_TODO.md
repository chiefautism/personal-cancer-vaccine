# TCR002361 Follicular Lymphoma — Next Run

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

## What Went Wrong

- fasterq-dump failed with DNS error: `connection not found while validating within network system module`
- SSH connections becoming unstable after 8+ hours on same instance
- Consider fresh instance for this run

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
