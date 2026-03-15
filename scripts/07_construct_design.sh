#!/usr/bin/env bash
set -euo pipefail

# Step 7: Assemble full mRNA vaccine construct
# Takes top neoantigens → builds polyepitope protein → optimizes with LinearDesign → adds UTRs
#
# Output: results/vaccine_construct/
#   - vaccine_protein.fasta      — polyepitope protein sequence
#   - vaccine_mrna_cds.fasta     — LinearDesign-optimized coding sequence
#   - vaccine_mrna_full.fasta    — complete mRNA with 5'UTR, Kozak, CDS, stop, 3'UTR, polyA
#   - construct_map.txt          — annotated map of the full construct

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "══════════════════════════════════════"
echo " Step 7: mRNA Vaccine Construct Design"
echo "══════════════════════════════════════"

python3 "$SCRIPT_DIR/utils/assemble_construct.py" \
    "$REPO_ROOT/results/real_top10.tsv" \
    "$REPO_ROOT/results/vaccine_construct"
