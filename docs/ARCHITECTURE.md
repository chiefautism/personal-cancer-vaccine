# Architecture

## Pipeline DAG

```
Tumor FASTQ ──→ BWA-MEM ──→ Tumor BAM ──┐
                                          ├──→ Mutect2 ──→ Filtered VCF ──→ VEP ──→ pVACseq ──→ Neoantigens
Normal FASTQ ─→ BWA-MEM ──→ Normal BAM ──┘                                           ↑
                                                                                      │
Tumor FASTQ ──→ OptiType ──→ HLA alleles ────────────────────────────────────────────┘
                                                                                      │
                                                              ColabFold ←── Top peptides
```

## Docker Images

| Step | Image | Size | Platform |
|------|-------|------|----------|
| Alignment | `biocontainers/bwa:v0.7.17_cv1` | ~200MB | linux/amd64 |
| Variant Calling | `broadinstitute/gatk:4.6.1.0` | ~1.5GB | linux/amd64 |
| HLA Typing | `fred2/optitype:latest` | ~800MB | linux/amd64 |
| VEP Annotation | `ensemblorg/ensembl-vep:release_113.0` | ~1.2GB | linux/amd64 |
| Neoantigen Prediction | `griffithlab/pvactools:6.1.0` | ~2GB | linux/amd64 |

## Resource Requirements by Step

| Step | CPU | RAM | Disk | Time (WGS) |
|------|-----|-----|------|-------------|
| 1. Alignment | 4 cores | 16GB | 80GB | 8-10h |
| 2. Variant Calling | 4 cores | 16GB | 20GB | 4-6h |
| 3. HLA Typing | 2 cores | 4GB | 1GB | 15-30min |
| 4. VEP Annotation | 2 cores | 8GB | 15GB | 30-60min |
| 5. pVACseq | 4 cores | 8GB | 2GB | 30-90min |
| 6. Post-processing | 1 core | 1GB | <1GB | <1min |

## Swappable Components

| Default | Alternative | Notes |
|---------|-------------|-------|
| BWA-MEM | Minimap2 | Faster, similar accuracy |
| Mutect2 | Strelka2 | Faster, may miss some low-VAF variants |
| OptiType | arcasHLA | Can also type Class II from RNA-seq |
| VEP | SnpEff | Requires different annotation format for pVACseq |
| MHCflurryEL | NetMHCpanBA | Binding affinity (BA) vs eluted ligand (EL) |

## ARM Mac Compatibility (M1/M2/M3/M4)

All Docker images are `linux/amd64`. Docker Desktop on Apple Silicon runs these via Rosetta 2 emulation with `--platform linux/amd64`. Performance is ~30-50% slower than native. This is handled automatically by the pipeline scripts.
