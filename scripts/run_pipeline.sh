#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Personalized mRNA Cancer Vaccine — Neoantigen Prediction Pipeline
# Single script to run everything via Docker. No local installs needed.
#
# Usage:
#   bash scripts/run_pipeline.sh --mode easy     # 20 min, pre-processed data
#   bash scripts/run_pipeline.sh --mode full     # 18 hours, from raw FASTQ
#   bash scripts/run_pipeline.sh --mode full --skip-to 5   # Resume from step 5
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Defaults
MODE="easy"
SKIP_TO=0
CONFIG="$REPO_ROOT/config/pipeline_config.yaml"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)     MODE="$2";     shift 2 ;;
        --skip-to)  SKIP_TO="$2";  shift 2 ;;
        --config)   CONFIG="$2";   shift 2 ;;
        --help|-h)
            echo "Usage: bash scripts/run_pipeline.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --mode easy|full   Pipeline mode (default: easy)"
            echo "  --skip-to N        Skip to step N (1-6)"
            echo "  --config PATH      Config file path"
            echo ""
            echo "Easy Mode:  Uses pre-processed data, runs pVACseq only (~20 min)"
            echo "Full Mode:  Full pipeline from raw FASTQ (~18 hours, 32GB RAM)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Load env
if [ -f "$REPO_ROOT/.env" ]; then
    source "$REPO_ROOT/.env"
else
    cp "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"
    source "$REPO_ROOT/.env"
fi

START_TIME=$(date +%s)

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Personalized mRNA Cancer Vaccine — Neoantigen Pipeline     ║"
echo "║  Mode: $(printf '%-52s' "$MODE")║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check dependencies
echo "── Checking dependencies ──"
bash "$SCRIPT_DIR/utils/check_dependencies.sh" "$MODE"
echo ""

# ═══════════════════════════════════════════════════════════════════
# EASY MODE
# ═══════════════════════════════════════════════════════════════════
if [ "$MODE" = "easy" ]; then

    # Download pre-processed inputs if needed
    if [ ! -d "$REPO_ROOT/data/easy_mode/HCC1395_inputs" ]; then
        echo "── Downloading Easy Mode inputs ──"
        bash "$SCRIPT_DIR/download_easy_mode_inputs.sh"
        echo ""
    fi

    # Validate
    bash "$SCRIPT_DIR/utils/validate_inputs.sh" easy "$REPO_ROOT"
    echo ""

    # Pull Docker image
    echo "── Pulling pVACtools Docker image ──"
    docker pull "griffithlab/pvactools:${PVACTOOLS_VERSION:-6.1.0}"
    echo ""

    # Run pVACseq
    echo "── Running pVACseq ──"
    bash "$SCRIPT_DIR/05_pvacseq.sh" easy

    # Post-process
    echo ""
    echo "── Post-processing ──"
    bash "$SCRIPT_DIR/06_postprocess.sh"

# ═══════════════════════════════════════════════════════════════════
# FULL MODE
# ═══════════════════════════════════════════════════════════════════
elif [ "$MODE" = "full" ]; then

    # Validate inputs
    bash "$SCRIPT_DIR/utils/validate_inputs.sh" full "$REPO_ROOT"
    echo ""

    # Pull all Docker images
    echo "── Pulling Docker images ──"
    docker pull biocontainers/bwa:v0.7.17_cv1
    docker pull "broadinstitute/gatk:${GATK_VERSION:-4.6.1.0}"
    docker pull fred2/optitype:latest
    docker pull "ensemblorg/ensembl-vep:release_${VEP_VERSION:-113}.0"
    docker pull "griffithlab/pvactools:${PVACTOOLS_VERSION:-6.1.0}"
    echo ""

    # Step 1: Alignment
    if [ "$SKIP_TO" -le 1 ]; then
        echo "── Step 1/6: BWA-MEM Alignment ──"
        bash "$SCRIPT_DIR/01_alignment.sh"
        echo ""
    fi

    # Step 2: Variant Calling
    if [ "$SKIP_TO" -le 2 ]; then
        echo "── Step 2/6: GATK Mutect2 ──"
        bash "$SCRIPT_DIR/02_variant_calling.sh"
        echo ""
    fi

    # Step 3: HLA Typing
    if [ "$SKIP_TO" -le 3 ]; then
        echo "── Step 3/6: OptiType HLA Typing ──"
        bash "$SCRIPT_DIR/03_hla_typing.sh"
        echo ""
    fi

    # Step 4: VEP Annotation
    if [ "$SKIP_TO" -le 4 ]; then
        echo "── Step 4/6: VEP Annotation ──"
        bash "$SCRIPT_DIR/04_vep_annotation.sh"
        echo ""
    fi

    # Step 5: pVACseq
    if [ "$SKIP_TO" -le 5 ]; then
        echo "── Step 5/6: pVACseq ──"
        bash "$SCRIPT_DIR/05_pvacseq.sh" full
        echo ""
    fi

    # Step 6: Post-processing
    if [ "$SKIP_TO" -le 6 ]; then
        echo "── Step 6/6: Post-processing ──"
        bash "$SCRIPT_DIR/06_postprocess.sh"
    fi

else
    echo "ERROR: Unknown mode '$MODE'. Use 'easy' or 'full'."
    exit 1
fi

# Summary
END_TIME=$(date +%s)
ELAPSED=$(( (END_TIME - START_TIME) / 60 ))

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Pipeline complete!                                         ║"
echo "║  Runtime: ${ELAPSED} minutes                                        ║"
echo "║                                                             ║"
echo "║  Results:                                                   ║"
echo "║    results/top10_neoantigens.tsv                            ║"
echo "║    results/colabfold_input.fasta                            ║"
echo "║                                                             ║"
echo "║  Next step: 3D structure prediction                         ║"
echo "║    Open notebooks/colabfold_neoantigen_structures.ipynb     ║"
echo "║    in Google Colab (free GPU)                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
