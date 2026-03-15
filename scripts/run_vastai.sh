#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Run the full neoantigen pipeline on Vast.ai (~$2-5 per patient)
#
# Recommended instance: RTX 3090 (24GB VRAM), 32GB+ RAM, 16 cores, 200GB disk
# Estimated cost: ~$0.20/hr × 12-18hr = $2.40-$3.60
#
# Prerequisites:
#   uv tool install vastai
#   vastai set api-key YOUR_API_KEY
#
# Usage:
#   bash scripts/run_vastai.sh                    # Full pipeline + ColabFold
#   bash scripts/run_vastai.sh --easy             # Easy mode only
#   bash scripts/run_vastai.sh --structure-only   # ColabFold only (after local run)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# ─── Configuration ───────────────────────────────────────────────────────────

# GPU Requirements by task:
#
# ┌─────────────────────┬────────────┬──────────┬───────────┬────────────────┐
# │ Step                │ Tool       │ GPU?     │ VRAM      │ Time           │
# ├─────────────────────┼────────────┼──────────┼───────────┼────────────────┤
# │ Alignment           │ BWA-MEM    │ CPU only │ -         │ 8-10h (WGS)    │
# │ Variant Calling     │ Mutect2    │ CPU only │ -         │ 4-6h           │
# │ HLA Typing          │ OptiType   │ CPU only │ -         │ 15-30min       │
# │ VEP Annotation      │ VEP        │ CPU only │ -         │ 30-60min       │
# │ Neoantigen Predict  │ pVACseq    │ CPU only │ -         │ 30-90min       │
# │ Structure Predict   │ ColabFold  │ YES      │ 16-24GB   │ 5-15min/struct │
# └─────────────────────┴────────────┴──────────┴───────────┴────────────────┘
#
# GPU-accelerated alternative (optional, not default):
#   NVIDIA Clara Parabricks can GPU-accelerate BWA-MEM + Mutect2 (35-50x speedup)
#   but requires: A100/H100, 100GB+ RAM, commercial license
#   We use standard CPU tools — simpler, cheaper, open-source.

# Instance search filters
MIN_GPU_RAM=16          # GB — 16GB minimum (T4), 24GB recommended (RTX 3090)
MIN_RAM=32              # GB system RAM
MIN_DISK=200            # GB disk space
MIN_CPU=8               # CPU cores
MAX_PRICE=0.40          # $/hr — keeps total cost under ~$5 for full pipeline

# Preferred GPUs (best value for this workload)
# RTX 3090: 24GB, ~$0.15-0.25/hr — sweet spot
# RTX 4090: 24GB, ~$0.30-0.55/hr — faster, same VRAM
# A6000:    48GB, ~$0.35-0.60/hr — overkill but comfortable
PREFERRED_GPU="RTX_3090"

MODE="full"
while [[ $# -gt 0 ]]; do
    case $1 in
        --easy)            MODE="easy";           shift ;;
        --structure-only)  MODE="structure-only";  shift ;;
        --gpu)             PREFERRED_GPU="$2";     shift 2 ;;
        --max-price)       MAX_PRICE="$2";         shift 2 ;;
        --help|-h)
            echo "Usage: bash scripts/run_vastai.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --easy              Easy mode (pVACseq only, ~20 min, ~\$0.10)"
            echo "  --structure-only    ColabFold only (bring your own neoantigens)"
            echo "  --gpu MODEL         Preferred GPU (default: RTX_3090)"
            echo "  --max-price RATE    Max \$/hr (default: 0.40)"
            echo ""
            echo "Recommended GPUs for Vast.ai:"
            echo "  RTX_3090  24GB  ~\$0.20/hr  Best value (recommended)"
            echo "  RTX_4090  24GB  ~\$0.40/hr  Faster inference"
            echo "  A6000     48GB  ~\$0.50/hr  Large complexes"
            echo "  A100_40GB 40GB  ~\$0.90/hr  Overkill for this pipeline"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ─── Preflight checks ───────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Vast.ai Pipeline Launcher                                  ║"
echo "║  Mode: $(printf '%-52s' "$MODE")║"
echo "║  GPU:  $(printf '%-52s' "$PREFERRED_GPU (${MIN_GPU_RAM}GB+ VRAM)")║"
echo "║  Max:  $(printf '%-52s' "\$${MAX_PRICE}/hr")║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if ! command -v vastai &>/dev/null; then
    echo "ERROR: vastai CLI not found."
    echo ""
    echo "Install:"
    echo "  uv tool install vastai"
    echo "  vastai set api-key YOUR_API_KEY"
    echo ""
    echo "Get your API key at: https://cloud.vast.ai/cli/"
    exit 1
fi

# Verify API key
if ! vastai show user &>/dev/null 2>&1; then
    echo "ERROR: Vast.ai API key not set or invalid."
    echo "Run: vastai set api-key YOUR_API_KEY"
    exit 1
fi

echo "── Searching for instances ──"
echo "  Filters: ${MIN_GPU_RAM}GB+ VRAM, ${MIN_RAM}GB+ RAM, ${MIN_CPU}+ CPUs, ${MIN_DISK}GB+ disk"
echo ""

# ─── Find best instance ─────────────────────────────────────────────────────

# Search for suitable instances
# Sort by price ascending — cheapest first
SEARCH_QUERY="gpu_ram>=${MIN_GPU_RAM} ram>=${MIN_RAM} cpu_cores>=${MIN_CPU} disk_space>=${MIN_DISK} dph<=${MAX_PRICE} inet_down>=200 reliability>0.95 rentable=true"

echo "  Searching Vast.ai marketplace..."
OFFERS=$(vastai search offers "$SEARCH_QUERY" --order "dph" --limit 5 --raw 2>/dev/null) || {
    echo "ERROR: No instances found matching criteria."
    echo "Try increasing --max-price or relaxing GPU requirements."
    exit 1
}

if [ -z "$OFFERS" ] || [ "$OFFERS" = "[]" ]; then
    echo "ERROR: No instances found. Try:"
    echo "  --max-price 0.60"
    echo "  or reduce MIN_GPU_RAM to 16"
    exit 1
fi

echo ""
echo "  Top 5 available instances:"
vastai search offers "$SEARCH_QUERY" --order "dph" --limit 5 2>/dev/null || true
echo ""

# Get cheapest instance ID
INSTANCE_ID=$(echo "$OFFERS" | python3 -c "
import json, sys
offers = json.load(sys.stdin)
if offers:
    print(offers[0]['id'])
" 2>/dev/null)

if [ -z "$INSTANCE_ID" ]; then
    echo "ERROR: Could not parse instance offers."
    exit 1
fi

INSTANCE_PRICE=$(echo "$OFFERS" | python3 -c "
import json, sys
offers = json.load(sys.stdin)
if offers:
    print(f\"\${offers[0].get('dph_total', 0):.3f}/hr\")
" 2>/dev/null)

echo "  Selected instance: #$INSTANCE_ID at $INSTANCE_PRICE"
echo ""

# ─── Build on-instance script ────────────────────────────────────────────────

ONSTART_SCRIPT=$(cat <<'VASTEOF'
#!/bin/bash
set -euo pipefail

cd /workspace

# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env

# Clone the pipeline repo
if [ ! -d "llm-cure-cancer" ]; then
    git clone https://github.com/YOUR_USERNAME/llm-cure-cancer.git
fi
cd llm-cure-cancer
cp .env.example .env

# Install Python dependencies via uv
uv sync
# Install ColabFold for local GPU structure prediction
uv pip install "colabfold[alphafold] @ git+https://github.com/sokrypton/ColabFold"

echo "Setup complete. Ready to run pipeline."
VASTEOF
)

# ─── Launch instance ─────────────────────────────────────────────────────────

echo "── Launching instance ──"
read -p "  Rent instance #$INSTANCE_ID at $INSTANCE_PRICE? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Cancelled."
    exit 0
fi

echo "  Creating instance..."
CREATE_RESULT=$(vastai create instance "$INSTANCE_ID" \
    --image "pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime" \
    --disk "$MIN_DISK" \
    --onstart-cmd "bash -c '$(echo "$ONSTART_SCRIPT" | sed "s/'/'\\\\''/g")'" \
    --raw 2>/dev/null)

NEW_INSTANCE_ID=$(echo "$CREATE_RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('new_contract', data.get('id', '')))
" 2>/dev/null)

if [ -z "$NEW_INSTANCE_ID" ]; then
    echo "ERROR: Failed to create instance."
    echo "$CREATE_RESULT"
    exit 1
fi

echo "  Instance created: #$NEW_INSTANCE_ID"
echo ""
echo "── Waiting for instance to start ──"

# Wait for instance to be running
for i in $(seq 1 60); do
    STATUS=$(vastai show instance "$NEW_INSTANCE_ID" --raw 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('actual_status', 'unknown'))
" 2>/dev/null || echo "unknown")

    if [ "$STATUS" = "running" ]; then
        echo "  Instance is running!"
        break
    fi
    echo "  Status: $STATUS (attempt $i/60)"
    sleep 10
done

if [ "$STATUS" != "running" ]; then
    echo "ERROR: Instance did not start within 10 minutes."
    echo "Check: vastai show instance $NEW_INSTANCE_ID"
    exit 1
fi

# Get SSH connection details
SSH_CMD=$(vastai ssh-url "$NEW_INSTANCE_ID" 2>/dev/null || true)

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Instance ready!                                            ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                             ║"
echo "║  SSH into the instance:                                     ║"
echo "║  $SSH_CMD"
echo "║                                                             ║"
echo "║  Then run the pipeline:                                     ║"
echo "║                                                             ║"
if [ "$MODE" = "easy" ]; then
echo "║    cd /workspace/llm-cure-cancer                            ║"
echo "║    bash easy_mode/run_easy_mode.sh                          ║"
echo "║    uv run python scripts/utils/visualize_neoantigens.py \\   ║"
echo "║      results/top10_neoantigens.tsv                          ║"
elif [ "$MODE" = "structure-only" ]; then
echo "║    cd /workspace/llm-cure-cancer                            ║"
echo "║    # Upload your colabfold_input.fasta first                ║"
echo "║    colabfold_batch input.fasta structures/ \\               ║"
echo "║      --num-models 3 --amber --num-recycle 3                 ║"
else
echo "║    cd /workspace/llm-cure-cancer                            ║"
echo "║    bash scripts/download_demo_data.sh                       ║"
echo "║    bash scripts/download_references.sh                      ║"
echo "║    bash scripts/run_pipeline.sh --mode full                 ║"
echo "║    uv run python scripts/utils/visualize_neoantigens.py \\   ║"
echo "║      results/top10_neoantigens.tsv                          ║"
fi
echo "║                                                             ║"
echo "║  When done, destroy the instance:                           ║"
echo "║    vastai destroy instance $NEW_INSTANCE_ID                       ║"
echo "║                                                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Monitor: vastai show instance $NEW_INSTANCE_ID"
echo "Logs:    vastai logs $NEW_INSTANCE_ID"
