# What To Do With Neoantigen Predictions

## What We Have

The pipeline produced **29,031 filtered peptide-MHC binding predictions** from the HCC1395 breast cancer cell line. The top 10 candidates (ranked by binding percentile):

| Gene | HLA | Peptide | Percentile | VAF | Expression (TPM) |
|------|-----|---------|-----------|-----|-----------------|
| TLN2 | HLA-B*08:01 | TPKFKQQL | 0.01 | 0.45 | 20.0 |
| TRPM7 | HLA-B*08:01 | ELHPRITQL | 0.01 | 0.50 | 28.6 |
| SMOX | HLA-B*08:01 | VLKRKYTSF | 0.01 | 0.60 | 34.5 |
| PRELID2 | HLA-B*08:01 | NMAIRSHRL | 0.02 | 0.32 | 7.1 |
| MAP7D1 | HLA-B*45:01 | KEKPIPQEP | 0.03 | 0.36 | 93.2 |
| SZT2 | HLA-C*06:02 | RRLHLPRHV | 0.03 | 0.34 | 34.7 |
| TESK1 | HLA-B*08:01 | YSLPRAAAL | 0.03 | 1.00 | 9.2 |
| SLC25A30 | HLA-C*06:02 | TRIMNQRVL | 0.03 | 0.45 | 20.3 |
| SLC25A30 | HLA-C*07:01 | TRIMNQRVL | 0.03 | 0.45 | 20.3 |
| ZNF548 | HLA-A*29:02 | VVFEYVAIY | 0.03 | 0.47 | 13.4 |

## What Each Column Means For Vaccine Design

- **Percentile < 0.5** = top 0.5% strongest binders. All our candidates are in the top 0.03%.
- **VAF > 0.3** = the mutation is present in >30% of tumor cells (clonal). Higher = more tumor cells will present this peptide. TESK1 at VAF=1.0 means it's in every tumor cell.
- **Expression > 5 TPM** = the gene is actively transcribed. MAP7D1 at 93 TPM is massively expressed — its peptide will be abundantly presented on tumor MHC.

## Step-by-Step: From This Data to a Vaccine

### 1. Validate neoantigens computationally (done / next steps)

- [x] Predict peptide-MHC binding (pVACseq — done)
- [ ] **3D structure prediction** — run ColabFold notebook (`notebooks/colabfold_neoantigen_structures.ipynb`) to visualize how each peptide sits in the MHC groove. Poor structural fit = likely false positive.
- [ ] **Reference proteome similarity** — check that the mutant peptide doesn't match any normal human protein (pVACseq does this with `--run-reference-proteome-similarity`). If it matches a self-protein, the immune system will be tolerant to it.
- [ ] **Cleavage prediction** — run NetChop or pVACseq's built-in proteasomal cleavage predictor to verify the peptide would actually be cleaved from the source protein by the proteasome.
- [ ] **Stability prediction** — run NetMHCstabpan to predict how long the peptide-MHC complex stays on the cell surface. Longer = better T-cell recognition.

### 2. Validate in the wet lab

- **Peptide-MHC tetramer assay** — synthesize the top peptides, fold them with recombinant HLA proteins, and test if patient T cells recognize them (ELISPOT or tetramer staining).
- **Immunogenicity assay** — stimulate patient PBMCs with each peptide and measure IFN-gamma secretion. Only peptides that actually activate T cells go into the vaccine.
- **Mass spectrometry (immunopeptidomics)** — if tumor tissue is available, directly detect which peptides are presented on tumor MHC by mass spec. This is the gold standard.

### 3. Design the mRNA vaccine construct

Once you have 5-20 validated neoantigens:

1. **Concatenate peptide sequences** — string them together with linker sequences (e.g., AAY or GGGGS linkers) that facilitate proteasomal cleavage between peptides.
2. **Add signal peptide** — prepend a secretory signal (e.g., tPA signal peptide) to route the polyprotein to the ER for MHC loading.
3. **Codon optimization** — optimize the mRNA codons for human expression (GC content, codon usage bias).
4. **Add UTR elements** — 5' cap (Cap1), optimized 5' UTR, poly(A) tail (100-150 nt), and potentially modified nucleotides (N1-methylpseudouridine) for stability and reduced innate immune activation.
5. **In vitro transcription** — produce the mRNA using T7 RNA polymerase from a linearized plasmid template.

### 4. Formulate in lipid nanoparticles (LNP)

- Standard LNP composition: ionizable lipid (e.g., SM-102 or ALC-0315), DSPC, cholesterol, PEG-lipid.
- Encapsulate mRNA at ~N/P ratio 6:1.
- Target size: 80-100 nm diameter.

### 5. Preclinical testing

- **In vitro**: transfect dendritic cells, co-culture with T cells, measure activation.
- **In vivo (mouse)**: HLA-transgenic mice or patient-derived xenografts. Measure tumor regression and T-cell infiltration.

### 6. Clinical administration

- Intramuscular or intravenous injection.
- Typical dose: 25-100 ug mRNA per injection.
- Schedule: prime + boost(s), often combined with checkpoint inhibitors (anti-PD-1).
- BioNTech/Moderna clinical trials use up to 34 neoantigens per patient.

## What This Pipeline Does NOT Do

| Step | Status | Who Does It |
|------|--------|-------------|
| Identify mutations | Done (Mutect2) | Pipeline |
| Predict HLA type | Done (OptiType) | Pipeline |
| Predict binding | Done (pVACseq) | Pipeline |
| Predict 3D structure | Available (ColabFold notebook) | Pipeline |
| Synthesize peptides for testing | Not in scope | Lab |
| Validate with T-cell assays | Not in scope | Lab |
| Design mRNA construct | Not in scope | Lab / bioinformatician |
| Produce mRNA | Not in scope | Lab (GMP facility) |
| Formulate LNP | Not in scope | Lab |
| Administer to patient | Not in scope | Clinic |

## Real-World Examples

- **BioNTech BNT122 (autogene cevumeran)** — personalized mRNA vaccine encoding up to 20 neoantigens per patient. Phase 2 for pancreatic cancer (2023-2025). Uses exactly this computational approach: WGS/WES + RNA-seq → neoantigen prediction → mRNA vaccine.
- **Moderna mRNA-4157 (V940)** — personalized neoantigen vaccine + pembrolizumab for melanoma. Phase 3 (KEYNOTE-942). 34 neoantigens per patient.
- **Paul Cunningham / UNSW** — used a similar pipeline for their personalized dog cancer vaccine project.

## How To Run This On Your Own Tumor Data

1. Get tumor + matched normal whole exome sequencing (WES) or whole genome sequencing (WGS)
2. Optionally: tumor RNA-seq for expression data
3. Edit `config/pipeline_config.yaml` with your sample info
4. Run: `bash scripts/run_pipeline.sh --mode full`
5. Top neoantigens will be in `results/top10_neoantigens.tsv`
6. Take them to a lab for validation

## Vast.ai Pipeline Run Log

What we actually did to get these results:

```
# 1. Rented RTX 5080 instance in California ($0.12/hr)
vastai create instance 29074977 --image pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime --disk 80

# 2. Installed dependencies
apt-get install unzip gcc g++ python3-dev zlib1g-dev python3-tk libx11-6
pip install pvactools==6.1.0
git clone --depth 1 https://github.com/KarchinLab/bigmhc.git /opt/bigmhc
pip install -e /opt/bigmhc

# 3. Fixed BigMHC wrapper (entry point not registered)
cat > /usr/local/bin/bigmhc_predict << 'EOF'
#!/bin/bash
python3 /opt/bigmhc/src/predict.py "$@"
EOF

# 4. Downloaded pre-processed HCC1395 data (~200MB)
bash scripts/download_easy_mode_inputs.sh

# 5. Ran pVACseq with NetMHCpanEL + BigMHC_EL
export MKL_THREADING_LAYER=GNU  # fix MKL/libgomp conflict
export CUDA_VISIBLE_DEVICES=""   # force CPU (PyTorch 2.2 doesn't support Blackwell sm_120)

pvacseq run \
  annotated.expression.vcf.gz \
  HCC1395_TUMOR_DNA \
  "HLA-A*29:02,HLA-B*08:01,HLA-B*45:01,HLA-C*06:02,HLA-C*07:01" \
  NetMHCpanEL BigMHC_EL \
  results/pvacseq \
  --normal-sample-name HCC1395_NORMAL_DNA \
  --pass-only --allele-specific-binding-thresholds \
  --percentile-threshold 2 --run-reference-proteome-similarity \
  -e1 8,9,10,11 --n-threads 14

# Result: 29,031 filtered epitopes in ~45 min
# Total cost: ~$0.50 (4 hours including setup/debugging)
```

### Gotchas We Hit

| Issue | Fix |
|-------|-----|
| BigMHC not in PATH | Create wrapper script at `/usr/local/bin/bigmhc_predict` |
| `MKL_THREADING_LAYER=INTEL` conflicts with libgomp | `export MKL_THREADING_LAYER=GNU` |
| MHCflurry `set_session` error with TF 2.21 | Use only NetMHCpanEL + BigMHC_EL (or downgrade TF to <2.16) |
| RTX 5080 (Blackwell sm_120) not supported by PyTorch 2.2 | `export CUDA_VISIBLE_DEVICES=""` to force CPU |
| SSH disconnects killing long-running processes | Use `nohup` for anything >5 min |
| pVACseq resumes from tmp files | It detects existing predictions and skips to the next |
