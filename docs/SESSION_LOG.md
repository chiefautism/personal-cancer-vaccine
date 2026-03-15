# Session Log — March 14-15, 2026

Everything that was built, run, and learned in one overnight session.

## What Was Built

### Pipeline code (30+ files)
- 7 bash scripts for each pipeline step (alignment through construct design)
- 3 Python utilities (report generator, visualizer, construct assembler)
- 1 ColabFold Jupyter notebook
- Docker compose with 5 services
- Vast.ai launch script
- Config files, download scripts, docs

### What Actually Ran Successfully

**pVACseq neoantigen prediction (Vast.ai, RTX 5080):**
- Input: HCC1395 pre-processed VEP-annotated VCF from griffithlab
- Algorithms: NetMHCpanEL + BigMHC_EL (MHCflurry failed due to TF/Keras incompatibility)
- HLA alleles: HLA-A*29:02, HLA-B*08:01, HLA-B*45:01, HLA-C*06:02, HLA-C*07:01
- Result: 29,031 filtered epitopes, 9 top neoantigens (all percentile <0.03)
- Time: ~45 min on CPU
- File: results/pvacseq/MHC_Class_I/HCC1395_TUMOR_DNA.MHC_I.filtered.tsv (14MB)

**ColabFold structure prediction (Vast.ai, RTX 5080):**
- 9 peptide-MHC complexes predicted with AlphaFold2-Multimer v3
- 27 PDB files generated (9 x 3 models)
- All structures: pLDDT >95, ipTM >0.93 (excellent quality)
- Time: ~3 hours (18 min per complex)
- Model weights downloaded from ColabFold servers (~4GB, cached)
- Files: results/predictions/*/

**LinearDesign mRNA optimization (Vast.ai):**
- Optimized full 135aa polyepitope construct
- MFE: -279.7 kcal/mol, CAI: 0.761
- Required python2 + gflags (LinearDesign wrapper is python2-only)
- Time: <1 min
- Files: results/vaccine_construct/

**mRNA construct assembly (local):**
- 816 nt complete mRNA with BNT162b2-style UTRs
- Files: results/vaccine_construct/vaccine_mrna_full.fasta, construct_map.txt

**Visualizations (local):**
- 7 publication-quality plots + HTML report
- Auto-detects IC50 vs Percentile (handles NA gracefully)
- Files: results/figures/, sample_output/figures/

**Scrollytelling visualization (local):**
- Flat design dark pastel theme
- 7 sections with scroll animations
- Files: results/vaccine_story.html

## What Failed and How It Was Fixed

### Docker Desktop I/O error (local)
- Problem: docker pull griffithlab/pvactools:6.1.0 failed with I/O error on virtual disk
- Cause: 17GB free disk, Docker VM running out of space
- Fix: moved to Vast.ai instead of running locally

### Vast.ai instance #1 (RTX 5060 Ti, California) — bad internet
- Problem: GitHub downloads at 0 MB/s, BigMHC git clone hung forever
- Fix: destroyed instance, rented new one with better network

### BigMHC not in PATH
- Problem: `pip install -e .` installed BigMHC but did not create `bigmhc_predict` entry point
- Fix: created wrapper script at /usr/local/bin/bigmhc_predict:
  ```bash
  #!/bin/bash
  python3 /opt/bigmhc/src/predict.py "$@"
  ```

### MKL threading conflict
- Problem: `MKL_THREADING_LAYER=INTEL is incompatible with libgomp.so.1`
- Fix: `export MKL_THREADING_LAYER=GNU`

### MHCflurry TensorFlow/Keras incompatibility
- Problem: pvactools 6.1.0 installed TF 2.21 which removed `keras.backend.set_session`
- MHCflurry 2.0.6 requires TF <2.16
- Fix: dropped MHCflurry, used only NetMHCpanEL + BigMHC_EL
- Proper fix would be: `pip install tensorflow==2.15.0` before pvactools

### MHCflurry CUDA error
- Problem: `RuntimeError: Bad StatusOr access: CUDA Runtime error`
- Cause: MHCflurry tries CUDA but RTX 5080 (Blackwell sm_120) not supported by TF in container
- Fix: `export CUDA_VISIBLE_DEVICES=""` forces CPU-only

### PyTorch CUDA incompatibility
- Problem: RTX 5080 (sm_120 Blackwell) not supported by PyTorch 2.2.0 (max sm_90)
- Fix: CUDA_VISIBLE_DEVICES="" for BigMHC; ColabFold used JAX which was updated to support sm_120

### SSH disconnects killing long processes
- Problem: SSH connection drops after 10-15 min, killing pvacseq mid-run
- Fix: all long-running commands via `nohup ... &` with logging to /tmp/*.log

### pVACseq restart detection
- Problem: re-running pVACseq with different flags (--keep-tmp-files) causes "Restart inputs are different" error
- Fix: use exactly the same flags as previous run, or rm -rf results/pvacseq/*

### LinearDesign python2 requirement
- Problem: lineardesign wrapper script requires python2 + gflags
- Fix: `apt-get install python2` (gflags.py bundled in LinearDesign repo)

### Visualization IC50 all zeros
- Problem: NetMHCpanEL + BigMHC_EL return percentile but not IC50 (NA in Best_IC50 column)
- Fix: rewrote visualize_neoantigens.py to auto-detect metric — uses Percentile when IC50 is NA

### generate_report.py column mismatch
- Problem: pVACseq output column names differ between versions (Gene vs Gene Name, etc)
- Fix: COLUMN_MAP dict maps both formats to canonical names

## Vast.ai Usage

### Instances rented:
1. RTX 5060 Ti (California) — $0.07/hr — killed (bad internet)
2. RTX 5060 Ti (California) — $0.07/hr — killed (bad internet, same host)
3. RTX 5080 (California) — $0.12/hr — used for everything, still running

### Total Vast.ai spend: ~$1 (estimated 8 hours at $0.12/hr)

### Instance setup recipe (what works):
```bash
apt-get install -y unzip gcc g++ python3-dev zlib1g-dev python3-tk libx11-6 python2
pip install pvactools==6.1.0
git clone --depth 1 https://github.com/KarchinLab/bigmhc.git /opt/bigmhc
pip install -e /opt/bigmhc
echo '#!/bin/bash\npython3 /opt/bigmhc/src/predict.py "$@"' > /usr/local/bin/bigmhc_predict
chmod +x /usr/local/bin/bigmhc_predict
pip install matplotlib seaborn
pip install --upgrade "jax[cuda12]"
pip install "colabfold[alphafold] @ git+https://github.com/sokrypton/ColabFold"
```

### Environment variables needed:
```bash
export MKL_THREADING_LAYER=GNU
export CUDA_VISIBLE_DEVICES=""   # for pVACseq/BigMHC (force CPU)
# ColabFold uses JAX+CUDA natively (don't set CUDA_VISIBLE_DEVICES for it)
```

## Top 9 Neoantigens (Real Results)

| Rank | Gene | Peptide | HLA | Percentile | VAF | Expression |
|------|------|---------|-----|-----------|-----|-----------|
| 1 | TLN2 | TPKFKQQL | B*08:01 | 0.01% | 0.452 | 20.0 |
| 2 | TRPM7 | ELHPRITQL | B*08:01 | 0.01% | 0.500 | 28.6 |
| 3 | SMOX | VLKRKYTSF | B*08:01 | 0.01% | 0.600 | 34.5 |
| 4 | PRELID2 | NMAIRSHRL | B*08:01 | 0.02% | 0.324 | 7.1 |
| 5 | MAP7D1 | KEKPIPQEP | B*45:01 | 0.03% | 0.361 | 93.2 |
| 6 | SZT2 | RRLHLPRHV | C*06:02 | 0.03% | 0.338 | 34.7 |
| 7 | TESK1 | YSLPRAAAL | B*08:01 | 0.03% | 1.000 | 9.2 |
| 8 | SLC25A30 | TRIMNQRVL | C*06:02 | 0.03% | 0.451 | 20.3 |
| 9 | ZNF548 | VVFEYVAIY | A*29:02 | 0.03% | 0.468 | 13.4 |

## Vaccine Construct

- 135 amino acids (tPA signal + 9 epitopes + 8 AAY linkers)
- 816 nucleotides (full mRNA with UTRs and polyA)
- LinearDesign optimized: MFE -279.7 kcal/mol, CAI 0.761
- Architecture: BNT162b2-style (alpha-globin 5'UTR, AES+mtRNR1 3'UTR, A30-linker-A70 polyA)

## Files Generated

```
results/
├── real_top10.tsv                          # 9 neoantigens from pVACseq
├── colabfold_input.fasta                   # peptide sequences for ColabFold
├── pvacseq/MHC_Class_I/
│   └── HCC1395_TUMOR_DNA.MHC_I.filtered.tsv  # 29,031 filtered epitopes
├── predictions/                            # 27 PDB files (9 complexes x 3 models)
│   ├── MAP7D1/
│   ├── PRELID2/
│   ├── SLC25A30/
│   ├── SMOX/
│   ├── SZT2/
│   ├── TESK1/
│   ├── TLN2/
│   ├── TRPM7/
│   └── ZNF548/
├── vaccine_construct/
│   ├── vaccine_protein.fasta               # 135 aa polyepitope
│   ├── vaccine_mrna_cds.fasta              # 405 nt CDS (codon optimized)
│   ├── vaccine_mrna_full.fasta             # 816 nt complete mRNA
│   ├── construct_map.txt                   # annotated construct map
│   └── lineardesign_output.txt             # LinearDesign raw output
├── figures/                                # 7 PNG plots + HTML report
│   ├── dashboard.png
│   ├── ranked.png
│   ├── peptide.png
│   ├── landscape.png
│   ├── hla.png
│   ├── vaf_expr.png
│   ├── chromo.png
│   └── report.html
├── vaccine_story.html                      # scrollytelling visualization
└── structures_viewer.html                  # Mol* 3D viewer (broken, needs HTTP server)
```

## What Was NOT Done

- Full mode from raw FASTQ (alignment + variant calling) — only easy mode was run
- MHCflurry predictions — incompatible TF version
- RNA-seq integration — used pre-computed expression from griffithlab
- MHC Class II predictions
- Fusion neoantigen detection
- HLA LOH detection
- COLO829 melanoma dataset — started but not completed
- Canine genome branch
- Nextflow/Snakemake wrapper
- GitHub Actions CI/CD
