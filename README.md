<p align="center">
  <img src="logo.png" width="200" alt="Personal Cancer Vaccine Pipeline">
</p>

# Personal Cancer Vaccine Pipeline

> **DISCLAIMER: This is a research and educational project. It is NOT a medical product, NOT clinically validated, and NOT approved for use in humans or animals. This pipeline produces computational predictions only -- it does not manufacture, test, or administer any vaccine. Do not use this software to make medical decisions. Any therapeutic application requires extensive wet-lab validation, preclinical testing, regulatory approval, and clinical oversight by qualified medical professionals. The authors assume no liability for any use of this software.**

---

## Table of Contents

- [Why This Exists](#why-this-exists)
- [How It Works: 9 Steps from Tumor DNA to Vaccine](#how-it-works-9-steps-from-tumor-dna-to-vaccine)
  - [Step 1 -- DNA Sequencing](#step-1--dna-sequencing)
  - [Step 2 -- Read Alignment (BWA-MEM)](#step-2--read-alignment-bwa-mem)
  - [Step 3 -- Finding Mutations (GATK Mutect2)](#step-3--finding-mutations-gatk-mutect2)
  - [Step 4 -- HLA Typing (OptiType)](#step-4--hla-typing-optitype)
  - [Step 5 -- Variant Annotation (VEP)](#step-5--variant-annotation-vep)
  - [Step 6 -- Neoantigen Prediction (pVACseq)](#step-6--neoantigen-prediction-pvacseq)
  - [Step 7 -- 3D Structure Prediction (ColabFold)](#step-7--3d-structure-prediction-colabfold--alphafold2)
  - [Step 8 -- mRNA Vaccine Design (LinearDesign)](#step-8--mrna-vaccine-design-lineardesign)
  - [Step 9 -- Delivery (LNP Encapsulation)](#step-9--delivery-lnp-encapsulation)
- [Visualizations](#visualizations)
- [Quick Start](#quick-start)
- [Cost Breakdown](#cost-breakdown)
- [Using Your Own Data](#using-your-own-data)
- [Clinical Context](#clinical-context)
- [Project Structure](#project-structure)
- [TODO](#todo)
- [How This Was Built](#how-this-was-built)
- [Tool References](#tool-references)
- [License](#license)

---

## Why This Exists

<img src="https://i1.wp.com/i.dailymail.co.uk/1s/2026/03/14/02/107127215-15644819-image-a-59_1773456851465.jpg?w=634&resize=634,476&ssl=1" width="500" alt="Paul Conyngham and Rosie">

In March 2026, Paul Conyngham -- a Sydney tech entrepreneur with no biomedical degree -- used ChatGPT and AlphaFold to design a personalized mRNA cancer vaccine for his rescue dog Rosie. He paid $3,000 for genomic sequencing, used AI to identify neoantigens from the tumor mutations, and worked with Pall Thordarson at the UNSW RNA Institute to produce the actual mRNA vaccine. Rosie got her first injection in December 2025. The tumor shrank by 75%. Scientists called it the first personalized cancer vaccine ever designed for a dog.

He spent 3 months writing a 100-page ethics application just to get permission to treat his own pet. He spent two hours every night after work. He had no background in biology.

That story made me stay up all night asking Claude Code questions, running searches, reading papers, and building this pipeline from scratch. If one person with ChatGPT and determination can do this for a dog, what happens when you make the entire computational pipeline open-source, reproducible, and runnable for $1 on a rented GPU?

This repo is the result. Everything from raw tumor DNA to a ready-to-synthesize mRNA vaccine sequence, automated and documented.

I have no background in biology or medicine. I do not know how correct any of this is. The pipeline was built in one night by asking Claude Code to research, code, and run everything. If you are a bioinformatician, immunologist, or anyone who actually knows this field -- please look at this and tell me what is wrong, what is missing, and what is dangerous. Open an issue, submit a PR, or just roast me. I would rather be corrected than be confidently wrong about something this important.

Sources on Paul Conyngham and Rosie:
- [AI-Designed mRNA Vaccine Shrinks Dog's Cancer Tumor](https://awesomeagents.ai/news/ai-mrna-vaccine-dog-cancer-rosie/)
- [Tech entrepreneur uses ChatGPT to create personalised cancer vaccine for his dog](https://papalinc.com/tech-entrepreneur-uses-chatgpt-to-create-a-personalised-cancer-vaccine-for-his-dog-and-the-breakthrough-could-soon-help-humans-too/)
- [Rescue dog Rosie's cancer shrinks after world-first mRNA vaccine](https://tildes.net/~health/1t7r/rescue_dog_rosies_cancer_shrinks_after_world_first_mrna_vaccine)

---

End-to-end computational pipeline: from raw tumor sequencing data to a ready-to-synthesize personalized mRNA cancer vaccine sequence.

Identifies tumor-specific neoantigens, predicts 3D peptide-MHC structures with AlphaFold2, and designs an optimized mRNA construct using LinearDesign -- the same computational approach used by BioNTech and Moderna in clinical trials.

**Tested on HCC1395 (triple-negative breast cancer). Total compute cost: ~$1 on Vast.ai.**

---

## How It Works: 9 Steps from Tumor DNA to Vaccine

### Step 1 -- DNA Sequencing

Everything starts with two DNA samples: one from the **tumor** and one from **healthy tissue** (matched normal). Both are sequenced using [whole-exome or whole-genome sequencing](https://www.genome.gov/genetics-glossary/Whole-Genome-Sequencing), producing raw [FASTQ files](https://en.wikipedia.org/wiki/FASTQ_format) -- billions of short DNA reads.

For this demo we use [**HCC1395**](https://www.cellosaurus.org/CVCL_1249), a publicly available triple-negative breast cancer cell line, with its matched normal **HCC1395BL**. Data is on [ENA](https://www.ebi.ac.uk/ena/browser/view/ERR194146) (ERR194146, ERR194147).

```
Tumor sample:  HCC1395      (~8 mutations per megabase)
Normal sample: HCC1395BL    (matched blood-derived normal)
Genome build:  GRCh38 (hg38)
```

### Step 2 -- Read Alignment (BWA-MEM)

Raw sequencing reads are aligned to the [human reference genome (GRCh38)](https://www.ncbi.nlm.nih.gov/datasets/genome/GCF_000001405.26/) using [**BWA-MEM**](https://github.com/lh3/bwa) ([paper](https://arxiv.org/abs/1303.3997)). This maps each short DNA fragment to its position in the genome. After alignment, duplicates are marked ([GATK MarkDuplicates](https://gatk.broadinstitute.org/hc/en-us/articles/360037052812-MarkDuplicates-Picard)) and base quality scores are recalibrated ([BQSR](https://gatk.broadinstitute.org/hc/en-us/articles/360035890531-Base-Quality-Score-Recalibration-BQSR)).

```bash
bash scripts/01_alignment.sh
```

**Output:** sorted, deduplicated BAM files for tumor and normal.

### Step 3 -- Finding Mutations (GATK Mutect2)

[**GATK Mutect2**](https://gatk.broadinstitute.org/hc/en-us/articles/360037593851-Mutect2) ([tutorial](https://gatk.broadinstitute.org/hc/en-us/articles/360035531132--How-to-Call-somatic-mutations-using-GATK4-Mutect2)) compares the tumor BAM against the normal BAM to find [**somatic mutations**](https://en.wikipedia.org/wiki/Somatic_mutation) -- changes in DNA that exist only in the cancer cells, not in healthy tissue. These are the mutations that drive the cancer and can serve as vaccine targets.

The pipeline filters for high-confidence variants using [contamination estimation](https://gatk.broadinstitute.org/hc/en-us/articles/360036888972-CalculateContamination), orientation bias filtering, and a [panel of normals](https://gatk.broadinstitute.org/hc/en-us/articles/360035890631-Panel-of-Normals-PON).

```bash
bash scripts/02_variant_calling.sh
```

**Result: 879 somatic mutations** found in HCC1395.

### Step 4 -- HLA Typing (OptiType)

Every person's immune system uses [**HLA molecules**](https://en.wikipedia.org/wiki/Human_leukocyte_antigen) (Human Leukocyte Antigen) to present peptide fragments on cell surfaces. [T cells](https://en.wikipedia.org/wiki/T_cell) scan these peptides -- if they recognize a foreign peptide (like one from a mutation), they kill the cell.

[**OptiType**](https://github.com/FRED-2/OptiType) ([paper](https://academic.oup.com/bioinformatics/article/30/23/3310/206261)) determines the patient's HLA type from the sequencing data. This is critical because a peptide that binds strongly to one person's HLA may not bind at all to another's.

```bash
bash scripts/03_hla_typing.sh
```

**HCC1395 HLA type:**
| Locus | Allele 1 | Allele 2 |
|-------|----------|----------|
| HLA-A | A\*29:02 | A\*29:02 (homozygous) |
| HLA-B | B\*08:01 | B\*45:01 |
| HLA-C | C\*06:02 | C\*07:01 |

### Step 5 -- Variant Annotation (VEP)

[**Ensembl VEP**](https://www.ensembl.org/info/docs/tools/vep/index.html) (Variant Effect Predictor) ([paper](https://genomebiology.biomedcentral.com/articles/10.1186/s13059-016-0974-4)) annotates each mutation with its effect on proteins -- is it a [missense mutation](https://en.wikipedia.org/wiki/Missense_mutation)? Does it change an amino acid? Which gene and transcript does it affect? The [Frameshift](https://pvactools.readthedocs.io/en/latest/pvacseq/input_file_prep/vep.html) and Wildtype plugins are added because pVACseq needs them.

```bash
bash scripts/04_vep_annotation.sh
```

### Step 6 -- Neoantigen Prediction (pVACseq)

This is the core step. [**pVACseq**](https://pvactools.readthedocs.io/en/latest/pvacseq.html) ([paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC7056579/), [GitHub](https://github.com/griffithlab/pVACtools)) takes the annotated mutations + HLA alleles and predicts which mutant peptides will bind strongly to the patient's [MHC molecules](https://en.wikipedia.org/wiki/Major_histocompatibility_complex). It runs two prediction algorithms:

- [**NetMHCpanEL**](https://services.healthtech.dtu.dk/services/NetMHCpan-4.1/) -- eluted ligand predictor, the gold standard ([paper](https://academic.oup.com/nar/article/48/W1/W449/5837056))
- [**BigMHC_EL**](https://github.com/KarchinLab/bigmhc) -- deep learning-based predictor ([paper](https://www.cell.com/cell-systems/fulltext/S2405-4712(23)00336-7))

The pipeline tests all peptide lengths (8-11 amino acids) against all 5 HLA alleles, generating **29,031 peptide-MHC binding predictions**. These are filtered by binding percentile, and the top candidates are ranked.

```bash
bash scripts/05_pvacseq.sh
```

**Result: 9 top neoantigens** -- all in the top 0.03% of binding strength:

| Gene | Mutant Peptide | HLA Allele | Percentile | Tumor VAF | Expression |
|------|---------------|------------|-----------|-----------|-----------|
| TLN2 | TP**K**FKQQL | B\*08:01 | 0.01% | 45% | 20 TPM |
| TRPM7 | ELHPRI**T**QL | B\*08:01 | 0.01% | 50% | 29 TPM |
| SMOX | VLKR**K**YTSF | B\*08:01 | 0.01% | 60% | 35 TPM |
| PRELID2 | NMAIRSH**R**L | B\*08:01 | 0.02% | 32% | 7 TPM |
| MAP7D1 | KE**K**PIPQEP | B\*45:01 | 0.03% | 36% | 93 TPM |
| SZT2 | RRLHLP**R**HV | C\*06:02 | 0.03% | 34% | 35 TPM |
| TESK1 | **Y**SLPRAAAL | B\*08:01 | 0.03% | 100% | 9 TPM |
| SLC25A30 | TR**I**MNQRVL | C\*06:02 | 0.03% | 45% | 20 TPM |
| ZNF548 | VVFE**Y**VAIY | A\*29:02 | 0.03% | 47% | 13 TPM |

**Bold** = mutated amino acid residue. Lower percentile = stronger binding.

![Top neoantigens ranked by binding strength](sample_output/figures/ranked.png)

![Mutant vs wildtype peptide sequences](sample_output/figures/peptide.png)

### Step 7 -- 3D Structure Prediction (ColabFold / AlphaFold2)

For each neoantigen, [**ColabFold**](https://github.com/sokrypton/ColabFold) ([paper](https://www.nature.com/articles/s41592-022-01488-1)) runs [AlphaFold2-Multimer](https://www.deepmind.com/blog/alphafold-reveals-the-structure-of-the-protein-universe) to predict the 3D structure of the peptide-MHC complex -- how the mutant peptide physically sits in the [MHC binding groove](https://en.wikipedia.org/wiki/MHC_class_I#Structure). This validates that the peptide actually fits. See also: [Accurate modeling of peptide-MHC structures with AlphaFold](https://pmc.ncbi.nlm.nih.gov/articles/PMC10028922/).

Each complex has 3 chains:
- **Chain A:** HLA alpha chain (~275 residues)
- **Chain B:** Beta-2-microglobulin (~99 residues)
- **Chain C:** Neoantigen peptide (8-9 residues)

We predicted all 9 complexes on Vast.ai (RTX 5080, ~3 hours, ~$0.36):

| Gene | Peptide | HLA | pLDDT | ipTM |
|------|---------|-----|-------|------|
| TLN2 | TPKFKQQL | B\*08:01 | 95.9 | 0.930 |
| TRPM7 | ELHPRITQL | B\*08:01 | 97.3 | 0.940 |
| SMOX | VLKRKYTSF | B\*08:01 | 96.1 | 0.930 |
| PRELID2 | NMAIRSHRL | B\*08:01 | 95.9 | 0.930 |
| MAP7D1 | KEKPIPQEP | B\*45:01 | **97.4** | **0.950** |
| SZT2 | RRLHLPRHV | C\*06:02 | 95.4 | 0.930 |
| TESK1 | YSLPRAAAL | B\*08:01 | 96.2 | 0.930 |
| SLC25A30 | TRIMNQRVL | C\*06:02 | 97.0 | 0.940 |
| ZNF548 | VVFEYVAIY | A\*29:02 | 96.6 | 0.940 |

**pLDDT > 70 = confident structure. ipTM > 0.6 = confident interface. All 9 are excellent (>95, >0.93).**

27 PDB files generated (9 complexes x 3 models each).

### Step 8 -- mRNA Vaccine Design (LinearDesign)

Now we have validated neoantigens. [**LinearDesign**](https://github.com/LinearDesignSoftware/LinearDesign) ([Nature, 2023](https://www.nature.com/articles/s41586-023-06127-z)) optimizes the mRNA coding sequence for maximum structural stability and translation efficiency, using [lattice parsing](https://en.wikipedia.org/wiki/CYK_algorithm) from computational linguistics. It achieved [128x improvement in antibody response](https://www.eurekalert.org/news-releases/987999) compared to standard codon optimization.

The pipeline assembles a complete mRNA construct following the architecture of BioNTech's [BNT162b2 COVID-19 vaccine](https://pmc.ncbi.nlm.nih.gov/articles/PMC8310186/) ([reverse-engineered here](https://berthub.eu/articles/posts/reverse-engineering-source-code-of-the-biontech-pfizer-vaccine/)):

```
5'cap -- 5'UTR (a-globin) -- Kozak -- tPA signal -- [TLN2-AAY-TRPM7-AAY-...-ZNF548] -- Stop -- 3'UTR (AES+mtRNR1) -- polyA (A30-linker-A70)
```

| Element | Source | Length | Purpose |
|---------|--------|--------|---------|
| 5' UTR | Human a-globin | 34 nt | High translation efficiency |
| Kozak | GCCACC | 6 nt | Ribosome start codon recognition |
| tPA signal peptide | Tissue plasminogen activator | 93 nt (31 aa) | Routes protein to ER for MHC loading |
| 9 neoantigens | pVACseq top hits | variable | Vaccine antigens |
| AAY linkers | Standard | 9 nt each | Proteasomal cleavage sites |
| Stop | UGA+UAA | 6 nt | Double stop for reliability |
| 3' UTR | AES + mtRNR1 | 255 nt | mRNA stability (BNT162b2-style) |
| Poly(A) | A30-GCAUAUGACU-A70 | 110 nt | Protection from degradation |

```bash
bash scripts/07_construct_design.sh
```

**Result:**
- Protein: 135 amino acids
- mRNA: **816 nucleotides**
- MFE: -279.7 kcal/mol (very stable)
- CAI: 0.761 (good human codon usage)

### Step 9 -- Delivery (LNP Encapsulation)

The final mRNA sequence is ready for [**in-vitro transcription**](https://en.wikipedia.org/wiki/In_vitro_transcription) (IVT). During IVT:
- All U nucleotides are replaced with [**N1-methylpseudouridine**](https://en.wikipedia.org/wiki/N1-Methylpseudouridine) to reduce innate immune activation ([Kariko et al., 2008](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC2775451/))
- [**Cap1**](https://en.wikipedia.org/wiki/Five-prime_cap) structure is added co-transcriptionally

The mRNA is then encapsulated in a [**lipid nanoparticle**](https://en.wikipedia.org/wiki/Solid_lipid_nanoparticle) (LNP) for delivery -- the same technology used in [Moderna](https://en.wikipedia.org/wiki/Moderna_COVID-19_vaccine) and [Pfizer](https://en.wikipedia.org/wiki/Pfizer%E2%80%93BioNTech_COVID-19_vaccine) COVID-19 vaccines.

> **This step is done in a wet lab, not computationally.** The pipeline ends here with a ready-to-synthesize mRNA sequence. See [docs/WHAT_NEXT.md](docs/WHAT_NEXT.md) for detailed wet-lab next steps.

---

## Visualizations

The pipeline generates publication-quality plots from the neoantigen predictions:

![Summary dashboard](sample_output/figures/dashboard.png)

![Binding strength vs gene expression](sample_output/figures/landscape.png)

![Neoantigen distribution by HLA allele](sample_output/figures/hla.png)

![Tumor VAF vs gene expression](sample_output/figures/vaf_expr.png)

![Chromosomal distribution of mutations](sample_output/figures/chromo.png)

```bash
uv run python scripts/utils/visualize_neoantigens.py results/real_top10.tsv
```

---

## Quick Start

### Easy Mode (~20 min, any machine with Docker)

```bash
git clone https://github.com/chiefautism/personal-cancer-vaccine.git
cd personal-cancer-vaccine
cp .env.example .env
bash easy_mode/run_easy_mode.sh
```

### Cloud Mode (~$1, Vast.ai)

```bash
uv tool install vastai
vastai set api-key YOUR_KEY
bash scripts/run_vastai.sh --easy
```

### Full Mode (~18h, from raw FASTQ)

```bash
bash scripts/download_demo_data.sh      # ~40GB tumor + normal FASTQ
bash scripts/download_references.sh     # ~30GB GRCh38 + databases
bash scripts/run_pipeline.sh --mode full
```

---

## Cost Breakdown

### Easy Mode (pre-processed data, neoantigen prediction only)

| Resource | Cost |
|----------|------|
| Vast.ai RTX 5080 instance (~45 min) | $0.09 |
| **Total** | **~$0.10** |

Runs in ~20 minutes on any machine with Docker (free). Vast.ai optional for speed.

### Full Mode (raw FASTQ to complete mRNA vaccine)

| Step | Tool | Time | Vast.ai Cost |
|------|------|------|-------------|
| Download data | wget | 30 min | -- |
| Alignment | BWA-MEM | 8-10h | $0.96-1.20 |
| Variant calling | Mutect2 | 4-6h | $0.48-0.72 |
| HLA typing | OptiType | 15-30 min | $0.03-0.06 |
| VEP annotation | VEP | 30-60 min | $0.06-0.12 |
| Neoantigen prediction | pVACseq | 30-90 min | $0.06-0.18 |
| Structure prediction | ColabFold | 2-3h | $0.24-0.36 |
| mRNA optimization | LinearDesign | <1 min | $0.00 |
| Construct assembly | Python | instant | $0.00 |
| **Total** | | **~16-22h** | **$1.83-2.64** |

Based on Vast.ai RTX 5080 at $0.12/hr. Actual cost of our HCC1395 run: $0.96 (8 hours including setup, debugging, and all retries).

### What is NOT included in the cost

The computational pipeline ends at an mRNA sequence file. The following wet-lab costs are separate and not part of this project:

| Wet-lab step | Estimated cost | Who does it |
|-------------|---------------|-------------|
| Custom mRNA synthesis (IVT) | $500-2,000 | RNA synthesis company |
| LNP encapsulation | $1,000-5,000 | Formulation lab |
| Quality control | $2,000-10,000 | GMP lab |
| Preclinical testing | $50,000+ | Research institution |
| Clinical trial | $1M+ | Hospital / pharma |

---

## Using Your Own Data

1. Edit `.env` and `config/pipeline_config.yaml` with your sample names and FASTQ paths
2. `bash scripts/run_pipeline.sh --mode full`
3. `bash scripts/07_construct_design.sh`

Works with any human tumor/normal pair on GRCh38.

---

## Clinical Context

This pipeline replicates the computational approach used in real clinical programs:

| Program | Company | Phase | Neoantigens | Result |
|---------|---------|-------|-------------|--------|
| V940 (mRNA-4157) | Moderna/Merck | Phase 3 | Up to 34 | 49% reduction in melanoma recurrence at 3 years |
| BNT122 (autogene cevumeran) | BioNTech | Phase 2 | Up to 20 | 6/8 responders disease-free at 3 years (pancreatic) |
| Rosie (dog) | Paul Conyngham / UNSW | Case study | Custom | 75% tumor shrinkage with AI-designed mRNA vaccine |

---

## Project Structure

```
personal-cancer-vaccine/
├── scripts/
│   ├── run_pipeline.sh              # Master orchestrator
│   ├── run_vastai.sh                # Vast.ai cloud launcher
│   ├── 01_alignment.sh              # BWA-MEM + BQSR
│   ├── 02_variant_calling.sh        # Mutect2
│   ├── 03_hla_typing.sh             # OptiType
│   ├── 04_vep_annotation.sh         # VEP + plugins
│   ├── 05_pvacseq.sh                # Neoantigen prediction
│   ├── 06_postprocess.sh            # Reports + viz
│   ├── 07_construct_design.sh       # mRNA vaccine assembly
│   └── utils/
│       ├── visualize_neoantigens.py # 7 plots + HTML report
│       └── assemble_construct.py    # mRNA construct builder
├── notebooks/
│   └── colabfold_neoantigen_structures.ipynb
├── config/                          # Pipeline parameters
├── docker/                          # Docker compose
├── sample_output/                   # Pre-generated results + figures
├── docs/
│   ├── WHAT_NEXT.md                 # Wet-lab next steps
│   ├── ARCHITECTURE.md              # Technical details
│   └── TROUBLESHOOTING.md           # Common issues
└── results/                         # Pipeline output (gitignored)
```

---

## TODO

- [ ] RNA-seq integration (STAR + expression quantification)
- [ ] MHC Class II predictions (CD4+ T-cell epitopes)
- [ ] Fusion neoantigen detection (STAR-Fusion -> pVACfuse)
- [ ] HLA loss-of-heterozygosity detection
- [ ] Immunogenicity prediction (BigMHC_IM)
- [ ] Nextflow wrapper
- [ ] Canine genome branch (CanFam4 + DLA alleles)

---

## How This Was Built

This entire pipeline was built in one night by someone with no biology background, using Claude Code in research mode. Here is what I searched for, read, and used to put this together -- sorted by importance to the final result.

### Core pipeline design

These are the resources that directly shaped the architecture and code of this pipeline.

- [griffithlab pVACtools Intro Course](https://github.com/griffithlab/pVACtools_Intro_Course) -- the single most important resource. Pre-processed HCC1395 data, step-by-step tutorial. Easy Mode is based entirely on this.
- [Best practices for bioinformatic characterization of neoantigens for clinical utility](https://genomemedicine.biomedcentral.com/articles/10.1186/s13073-019-0666-2) -- Genome Medicine 2019. The definitive guide to neoantigen pipeline design. Defined the order of steps.
- [pVACtools documentation](https://pvactools.readthedocs.io/) -- how to run pVACseq, what algorithms to use, what the output columns mean, how to filter results.
- [GATK Best Practices for somatic variant calling](https://gatk.broadinstitute.org/hc/en-us/articles/360035894731-Somatic-short-variant-discovery-SNVs-Indels) -- Mutect2 tumor-normal workflow, contamination estimation, filtering.
- [ImmunoNX: bioinformatics workflow for neoantigen vaccine trials](https://pmc.ncbi.nlm.nih.gov/articles/PMC12709488/) -- 2025 paper. Validated that our pipeline steps match what is used in actual clinical trials.
- [OpenVax neoantigen vaccine pipeline](https://github.com/openvax/neoantigen-vaccine-pipeline) -- another open-source pipeline. Used for cross-referencing our approach.

### mRNA vaccine construct design

These sources defined how the final mRNA sequence is assembled -- UTRs, signal peptide, linkers, polyA.

- [Detailed Dissection and Critical Evaluation of the Pfizer/BioNTech and Moderna mRNA Vaccines](https://pmc.ncbi.nlm.nih.gov/articles/PMC8310186/) -- reverse-engineered BNT162b2 structure. This is where the 5'UTR, 3'UTR, and polyA design comes from.
- [Reverse Engineering the source code of the BioNTech/Pfizer SARS-CoV-2 Vaccine](https://berthub.eu/articles/posts/reverse-engineering-source-code-of-the-biontech-pfizer-vaccine/) -- Bert Hubert's blog post. Made the BNT162b2 architecture understandable.
- [BioNTech coronavirus vaccine patent WO2021213945A1](https://patents.google.com/patent/WO2021213945A1/en) -- actual patent with sequence details for UTRs and polyA.
- [Optimized polyepitope neoantigen DNA vaccines](https://genomemedicine.biomedcentral.com/articles/10.1186/s13073-021-00872-4) -- AAY linkers, polyepitope design, furin cleavage sites. Confirmed that AAY linkers work and furin sites are optional.
- [Algorithm for optimized mRNA design improves stability and immunogenicity](https://www.nature.com/articles/s41586-023-06127-z) -- LinearDesign Nature paper. 128x improvement in antibody response.
- [LinearDesign GitHub](https://github.com/LinearDesignSoftware/LinearDesign) -- the tool we used for mRNA codon optimization.
- [tPA signal sequence enhances immunogenicity of mRNA vaccines](https://link.springer.com/article/10.1186/s12951-024-02488-3) -- why we chose tPA as the signal peptide.
- [Modifications of mRNA vaccine structural elements for improving stability and translation](https://link.springer.com/article/10.1007/s13273-021-00171-4) -- why each structural element matters.
- [Evaluation of synthetic mRNA with selected UTR sequences and alternative poly(A) tail](https://pmc.ncbi.nlm.nih.gov/articles/PMC12355064/) -- 2025 paper on UTR optimization and segmented polyA.
- [Poly(A) tail with loop structure enhances translation](https://www.nature.com/articles/s41541-025-01287-7) -- npj Vaccines 2025.
- [mRNA-LNP vaccines combined with tPA signal sequences](https://journals.asm.org/doi/10.1128/msphere.00775-24) -- mSphere 2024.

### Clinical evidence that this approach works

These papers and press releases show that the same computational approach is being used in real clinical trials with real results.

- [Moderna V940 KEYNOTE-942: 3-year data](https://www.merck.com/news/moderna-merck-announce-3-year-data-for-mrna-4157-v940-in-combination-with-keytruda-pembrolizumab-demonstrated-sustained-improvement-in-recurrence-free-survival-distant-metastasis-free-su/) -- 49% reduction in melanoma recurrence. Phase 3 ongoing.
- [Moderna V940: 5-year follow-up](https://www.targetedonc.com/view/rfs-benefit-sustained-at-5-years-for-intismeran-autogene-in-melanoma) -- benefit sustained at 5 years.
- [BioNTech BNT122: 3-year pancreatic cancer data](https://investors.biontech.de/news-releases/news-release-details/three-year-phase-1-follow-data-mrna-based-individualized) -- 6/8 responders disease-free at 3 years.
- [Dana-Farber NeoVaxMI results](https://www.dana-farber.org/newsroom/news-releases/2025/modified-personalized-cancer-vaccine-generates-powerful-immune-response) -- 9/9 patients showed T-cell response.
- [Neoantigen DNA vaccines in triple-negative breast cancer patients](https://link.springer.com/article/10.1186/s13073-024-01388-3) -- Genome Medicine 2024. Directly relevant to HCC1395 (also TNBC).

### Immunology background

These helped me understand why neoantigens work as vaccine targets and what makes a good candidate.

- [Personalized neoantigen cancer vaccines: current progression, challenges and a bright future](https://pmc.ncbi.nlm.nih.gov/articles/PMC11427492/) -- comprehensive overview of the field.
- [Advances in the development of personalized neoantigen therapies](https://rupress.org/jem/article/223/2/e20241234/278560/) -- Journal of Experimental Medicine 2025.
- [Designing neoantigen cancer vaccines, trials, and outcomes](https://www.frontiersin.org/journals/immunology/articles/10.3389/fimmu.2023.1105420/full) -- Frontiers in Immunology.
- [Computational biology and AI in mRNA vaccine design for cancer immunotherapy](https://www.frontiersin.org/journals/cellular-and-infection-microbiology/articles/10.3389/fcimb.2024.1501010/full) -- Frontiers 2024.

### Structure prediction

- [ColabFold: making protein folding accessible to all](https://www.nature.com/articles/s41592-022-01488-1) -- Nature Methods 2022.
- [ColabFold GitHub](https://github.com/sokrypton/ColabFold) -- how to predict peptide-MHC structures, VRAM requirements.

### GPU and cloud compute

- [Vast.ai](https://vast.ai) -- where we ran everything ($0.12/hr for RTX 5080).
- [NVIDIA Clara Parabricks](https://www.nvidia.com/en-us/clara/parabricks/) -- GPU-accelerated variant calling. We did not use it, CPU was fine.

### Demo data

- [HCC1395 on Cellosaurus](https://www.cellosaurus.org/CVCL_1249) -- triple-negative breast cancer, ~8 mut/Mb, known HLA alleles.
- [griffithlab pVACtools course data](https://github.com/griffithlab/pVACtools_Intro_Course) -- pre-processed VCF, HLA types, expression data.
- [ENA ERR194146 / ERR194147](https://www.ebi.ac.uk/ena/) -- raw FASTQ files for HCC1395 and HCC1395BL.

### The starting point

- [AI-Designed mRNA Vaccine Shrinks Dog's Cancer Tumor](https://awesomeagents.ai/news/ai-mrna-vaccine-dog-cancer-rosie/) -- the Paul Conyngham story that started this whole thing.
- [Tech entrepreneur uses ChatGPT to create personalised cancer vaccine for his dog](https://papalinc.com/tech-entrepreneur-uses-chatgpt-to-create-a-personalised-cancer-vaccine-for-his-dog-and-the-breakthrough-could-soon-help-humans-too/)
- [DIY mRNA Cancer Vaccine with ChatGPT and AlphaFold: 2026 Analysis](https://blockchain.news/ainews/diy-mrna-cancer-vaccine-with-chatgpt-and-alphafold-2026-analysis-on-costs-workflow-and-risks) -- cost and workflow analysis.

Everything above is what Claude Code searched, read, and synthesized to build this pipeline. I asked questions, it found papers, I asked more questions, it wrote code, I ran it, it broke, we fixed it. Repeat for ~12 hours.

---

## Tool References

- **pVACtools**: Hundal et al. (2020) *Cancer Immunology Research*
- **GATK Mutect2**: Van der Auwera & O'Connor (2020) *O'Reilly*
- **BWA-MEM**: Li (2013) *arXiv:1303.3997*
- **OptiType**: Szolek et al. (2014) *Bioinformatics*
- **VEP**: McLaren et al. (2016) *Genome Biology*
- **ColabFold**: Mirdita et al. (2022) *Nature Methods*
- **LinearDesign**: Zhang et al. (2023) *Nature*
- **HCC1395 data**: Griffith Lab, Washington University School of Medicine

## License

MIT -- see [LICENSE](LICENSE).
