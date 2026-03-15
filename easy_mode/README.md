# Easy Mode

Run the neoantigen prediction pipeline in ~20 minutes on any machine with Docker and 16GB RAM.

## What it does

Skips alignment (BWA-MEM), variant calling (Mutect2), HLA typing (OptiType), and VEP annotation. Uses pre-processed inputs from the [griffithlab pVACtools Intro Course](https://github.com/griffithlab/pVACtools_Intro_Course) and runs pVACseq neoantigen prediction directly.

## Pre-processed inputs

| File | Description |
|------|-------------|
| `annotated.expression.vcf.gz` | VEP-annotated VCF with Frameshift/Wildtype plugins and gene expression data |
| `phased.vcf.gz` | Phased germline variants for proximal variant detection |
| `Homo_sapiens.GRCh38.pep.all.fa.gz` | Reference proteome for self-similarity filtering |

## HLA alleles (known for HCC1395)

- HLA-A\*29:02 (homozygous)
- HLA-B\*08:01
- HLA-B\*45:01
- HLA-C\*06:02
- HLA-C\*07:01

## Run

```bash
bash easy_mode/run_easy_mode.sh
```

## Output

`results/pvacseq/MHC_Class_I/HCC1395_TUMOR_DNA.filtered.tsv` — full pVACseq results
`results/top10_neoantigens.tsv` — ranked top 10 candidates
`results/colabfold_input.fasta` — peptide sequences for 3D structure prediction
