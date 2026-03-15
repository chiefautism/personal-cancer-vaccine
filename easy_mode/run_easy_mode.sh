#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Easy Mode — Run neoantigen prediction in ~20 minutes on any MacBook (16GB RAM)
# Uses pre-processed HCC1395 data from griffithlab. No alignment or variant
# calling needed — just pVACseq neoantigen prediction.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

exec bash "$REPO_ROOT/scripts/run_pipeline.sh" --mode easy
