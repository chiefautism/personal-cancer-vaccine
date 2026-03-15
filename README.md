# Personalized mRNA Cancer Vaccine Pipeline

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

End-to-end computational pipeline: from raw tumor sequencing data to a ready-to-synthesize mRNA vaccine sequence. Identifies tumor-specific neoantigens, predicts 3D peptide-MHC structures, and designs an optimized mRNA construct with LinearDesign.

**Tested on HCC1395 (triple-negative breast cancer). Total compute cost: ~$1 on Vast.ai.**

## What This Pipeline Produces

From a tumor + normal DNA sample, you get:

| Output | File | Description |
|--------|------|-------------|
| Top neoantigens | `results/real_top10.tsv` | 9 tumor-specific peptides ranked by MHC binding |
| 3D structures | `results/predictions/*/` | 27 PDB files (9 complexes x 3 models, ipTM >0.93) |
| mRNA vaccine | `results/vaccine_construct/vaccine_mrna_full.fasta` | 816 nt complete mRNA ready for IVT synthesis |
| Visualizations | `results/figures/report.html` | 7 plots + interactive HTML report |
| Pipeline story | `results/vaccine_story.html` | Scrollytelling visualization of the full pipeline |

## Pipeline

```
Tumor FASTQ ──→ BWA-MEM ──→ GATK Mutect2 ──→ VEP ──→ pVACseq ──→ Top Neoantigens
Normal FASTQ ─→ BWA-MEM ──┘                           ↑
                                                       │
Tumor FASTQ ──→ OptiType ──→ HLA alleles ─────────────┘
                                                       │
                              ColabFold ←── Top peptides ──→ PDB structures
                                                       │
                           LinearDesign ←── Peptide sequences ──→ Optimized mRNA
                                                       │
                    Construct assembly ←── mRNA CDS + UTRs + polyA ──→ Full mRNA vaccine
```

| Step | Tool | What it does | Time |
|------|------|-------------|------|
| 1 | BWA-MEM | Align reads to GRCh38 | 8-10h |
| 2 | GATK Mutect2 | Call somatic mutations | 4-6h |
| 3 | OptiType | Determine patient HLA type | 30 min |
| 4 | Ensembl VEP | Annotate variant consequences | 30 min |
| 5 | pVACseq | Predict neoantigen binding (NetMHCpanEL + BigMHC_EL) | 45 min |
| 6 | ColabFold | AlphaFold2-Multimer peptide-MHC structures | 3h |
| 7 | LinearDesign | Optimize mRNA codon usage + stability | 1 min |
| 8 | Construct assembly | Add UTRs, signal peptide, polyA (BNT162b2-style) | instant |

## Demo Results (HCC1395)

**Patient:** HCC1395 — triple-negative breast cancer cell line, matched normal HCC1395BL

**HLA type:** `A*29:02, B*08:01, B*45:01, C*06:02, C*07:01`

**Top 9 neoantigens identified:**

| Gene | Peptide | HLA | Percentile | VAF | Expression |
|------|---------|-----|-----------|-----|-----------|
| TLN2 | TP**K**FKQQL | B*08:01 | 0.01% | 0.45 | 20 TPM |
| TRPM7 | ELHPRI**T**QL | B*08:01 | 0.01% | 0.50 | 29 TPM |
| SMOX | VLKR**K**YTSF | B*08:01 | 0.01% | 0.60 | 35 TPM |
| PRELID2 | NMAIRSH**R**L | B*08:01 | 0.02% | 0.32 | 7 TPM |
| MAP7D1 | KE**K**PIPQEP | B*45:01 | 0.03% | 0.36 | 93 TPM |
| SZT2 | RRLHLP**R**HV | C*06:02 | 0.03% | 0.34 | 35 TPM |
| TESK1 | **Y**SLPRAAAL | B*08:01 | 0.03% | 1.00 | 9 TPM |
| SLC25A30 | TR**I**MNQRVL | C*06:02 | 0.03% | 0.45 | 20 TPM |
| ZNF548 | VVFE**Y**VAIY | A*29:02 | 0.03% | 0.47 | 13 TPM |

**Bold** = mutated residue. All peptides in top 0.03% of binding strength.

**3D structures:** All 9 peptide-MHC complexes predicted with pLDDT >95, ipTM >0.93 (excellent confidence).

**mRNA vaccine construct:** 816 nt, 135 aa polyepitope with tPA signal peptide, AAY linkers, BNT162b2-style UTRs.

## Quick Start

### Easy Mode (~20 min, any machine with Docker)

```bash
git clone https://github.com/ADA-BOOST/llm-cure-cancer.git
cd llm-cure-cancer
cp .env.example .env
bash easy_mode/run_easy_mode.sh
```

### Cloud Mode (~$1, full pipeline + structures on Vast.ai)

```bash
uv tool install vastai
vastai set api-key YOUR_KEY
bash scripts/run_vastai.sh --easy
```

### Full Mode (~18h, from raw FASTQ)

```bash
bash scripts/download_demo_data.sh      # ~40GB
bash scripts/download_references.sh     # ~30GB
bash scripts/run_pipeline.sh --mode full
```

## mRNA Vaccine Construct

The pipeline outputs a complete mRNA vaccine sequence ready for in-vitro transcription:

```
5'UTR (α-globin, 34nt) → Kozak → tPA signal → 9 neoantigens with AAY linkers → Stop → 3'UTR (AES+mtRNR1) → polyA (A30-linker-A70)
```

LinearDesign optimizes the coding sequence for:
- **Structural stability:** MFE -279.7 kcal/mol
- **Codon usage:** CAI 0.761 (human-optimized)

Design follows BioNTech BNT162b2 architecture. See [docs/WHAT_NEXT.md](docs/WHAT_NEXT.md) for wet-lab next steps.

## Visualizations

```bash
uv run python scripts/utils/visualize_neoantigens.py results/real_top10.tsv
```

Generates 7 publication-quality plots + self-contained HTML report:

![Dashboard](sample_output/figures/dashboard.png)

Interactive pipeline story: `results/vaccine_story.html` (serve via `python3 -m http.server`)

## Project Structure

```
llm-cure-cancer/
├── README.md
├── LICENSE
├── pyproject.toml                           # Python deps (uv sync)
├── .env.example
├── config/
│   ├── pipeline_config.yaml                 # All tunable parameters
│   ├── hla_alleles.txt                      # HCC1395 HLA alleles
│   └── prediction_algorithms.txt            # pVACseq algorithm config
├── docker/
│   └── docker-compose.yaml
├── scripts/
│   ├── run_pipeline.sh                      # Master orchestrator
│   ├── run_vastai.sh                        # Vast.ai cloud launcher
│   ├── download_easy_mode_inputs.sh         # Pre-processed data (~200MB)
│   ├── download_demo_data.sh                # Raw FASTQ (~40GB)
│   ├── download_references.sh               # GRCh38 + databases (~30GB)
│   ├── 01_alignment.sh                      # BWA-MEM + BQSR
│   ├── 02_variant_calling.sh                # Mutect2 + filtering
│   ├── 03_hla_typing.sh                     # OptiType HLA-I
│   ├── 04_vep_annotation.sh                 # VEP + plugins
│   ├── 05_pvacseq.sh                        # Neoantigen prediction
│   ├── 06_postprocess.sh                    # Reports + visualizations
│   ├── 07_construct_design.sh               # mRNA vaccine assembly
│   └── utils/
│       ├── generate_report.py               # TSV/FASTA output
│       ├── visualize_neoantigens.py         # 7 plots + HTML report
│       └── assemble_construct.py            # mRNA construct builder
├── easy_mode/
│   └── run_easy_mode.sh
├── notebooks/
│   └── colabfold_neoantigen_structures.ipynb
├── sample_output/
│   ├── top10_neoantigens.tsv                # Real pVACseq results
│   └── figures/                             # Pre-generated plots
├── results/                                 # Pipeline output (gitignored)
│   ├── real_top10.tsv
│   ├── vaccine_construct/
│   │   ├── vaccine_protein.fasta            # 135 aa polyepitope
│   │   ├── vaccine_mrna_full.fasta          # 816 nt complete mRNA
│   │   └── construct_map.txt                # Annotated construct map
│   ├── predictions/                         # ColabFold PDB structures
│   ├── figures/                             # Visualization output
│   └── vaccine_story.html                   # Interactive pipeline story
└── docs/
    ├── ARCHITECTURE.md
    ├── TROUBLESHOOTING.md
    └── WHAT_NEXT.md                         # From predictions to wet-lab
```

## Using Your Own Data

1. Edit `.env` and `config/pipeline_config.yaml` with your sample names and FASTQ paths
2. Run `bash scripts/run_pipeline.sh --mode full`
3. Run `bash scripts/07_construct_design.sh` to assemble the mRNA construct

Works with any human tumor/normal pair on GRCh38.

## Context

This pipeline replicates the computational approach used in:

- **Moderna V940 (mRNA-4157)** — personalized neoantigen vaccine, Phase 3 for melanoma. 49% reduction in recurrence at 3 years. Up to 34 neoantigens per patient.
- **BioNTech BNT122 (autogene cevumeran)** — Phase 2 for pancreatic cancer. 6/8 responders disease-free at 3 years.
- **Paul Conyngham / UNSW (2025)** — used ChatGPT + AlphaFold to design mRNA vaccine for his dog Rosie. Tumor shrank 75%.

## Vast.ai Run Log

Our actual run on Vast.ai (RTX 5080, $0.12/hr):
- pVACseq: 29,031 filtered epitopes in ~45 min
- ColabFold: 9 structures in ~3 hours
- LinearDesign: full construct in <1 min
- Total cost: ~$1

Known gotchas documented in [docs/WHAT_NEXT.md](docs/WHAT_NEXT.md#vastai-pipeline-run-log).

## TODO

- [ ] RNA-seq integration (STAR + expression quantification)
- [ ] MHC Class II predictions (CD4+ T-cell epitopes)
- [ ] Fusion neoantigen detection (STAR-Fusion → pVACfuse)
- [ ] HLA loss-of-heterozygosity detection
- [ ] Immunogenicity prediction (BigMHC_IM / DeepImmuno)
- [ ] Nextflow/Snakemake wrapper
- [ ] Canine genome branch (CanFam4 + DLA alleles)

## References

- **pVACtools**: Hundal et al. (2020) *Cancer Immunology Research*
- **GATK**: Van der Auwera & O'Connor (2020) O'Reilly
- **BWA-MEM**: Li (2013) *arXiv:1303.3997*
- **OptiType**: Szolek et al. (2014) *Bioinformatics*
- **VEP**: McLaren et al. (2016) *Genome Biology*
- **ColabFold**: Mirdita et al. (2022) *Nature Methods*
- **LinearDesign**: Zhang et al. (2023) *Nature*
- **HCC1395**: Griffith Lab, Washington University

## License

MIT — see [LICENSE](LICENSE).
