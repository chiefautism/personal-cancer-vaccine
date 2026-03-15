#!/usr/bin/env bash
set -euo pipefail

# Step 6: Post-processing — extract top-10 neoantigens + generate ColabFold input

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
source "$REPO_ROOT/.env" 2>/dev/null || true

TUMOR="${TUMOR_SAMPLE:-HCC1395_TUMOR_DNA}"
TOP_N="${TOP_N:-10}"

PVACSEQ_OUTPUT="$REPO_ROOT/results/pvacseq/MHC_Class_I/${TUMOR}.filtered.tsv"
OUTPUT_DIR="$REPO_ROOT/results"

echo "══════════════════════════════════════"
echo " Step 6: Post-processing"
echo "══════════════════════════════════════"

if [ ! -f "$PVACSEQ_OUTPUT" ]; then
    echo "ERROR: pVACseq output not found: $PVACSEQ_OUTPUT"
    echo "Run step 5 first."
    exit 1
fi

python3 "$SCRIPT_DIR/utils/generate_report.py" \
    "$PVACSEQ_OUTPUT" \
    "$TOP_N" \
    "$OUTPUT_DIR"

# Generate visualizations (if matplotlib is available)
if python3 -c "import matplotlib" 2>/dev/null; then
    echo ""
    echo "── Generating visualizations ──"
    python3 "$SCRIPT_DIR/utils/visualize_neoantigens.py" \
        "$OUTPUT_DIR/top10_neoantigens.tsv" \
        "$OUTPUT_DIR/figures"
else
    echo ""
    echo "NOTE: Install matplotlib for visualizations:"
    echo "  uv sync   # from repo root"
    echo "  python3 scripts/utils/visualize_neoantigens.py results/top10_neoantigens.tsv"
fi

echo ""
echo "Pipeline complete!"
echo ""
echo "Results:"
echo "  Top neoantigens:  results/top10_neoantigens.tsv"
echo "  ColabFold input:  results/colabfold_input.fasta"
echo "  Visualizations:   results/figures/ (if matplotlib available)"
echo "  HTML report:      results/figures/report.html"
echo "  Full pVACseq:     results/pvacseq/"
echo ""
echo "Next: Open notebooks/colabfold_neoantigen_structures.ipynb in Google Colab"
echo "      to predict 3D structures of the top peptide-MHC complexes."
