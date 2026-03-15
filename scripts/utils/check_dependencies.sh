#!/usr/bin/env bash
set -euo pipefail

# Verify runtime environment before pipeline execution

MODE="${1:-easy}"
ERRORS=0

echo "Checking dependencies for $MODE mode..."

# Docker
if ! command -v docker &>/dev/null; then
    echo "FAIL: Docker not installed. Get it at https://docker.com/products/docker-desktop"
    ERRORS=$((ERRORS + 1))
elif ! docker info &>/dev/null 2>&1; then
    echo "FAIL: Docker daemon not running. Start Docker Desktop."
    ERRORS=$((ERRORS + 1))
else
    echo "  OK: Docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
fi

# wget or curl
if command -v wget &>/dev/null; then
    echo "  OK: wget available"
elif command -v curl &>/dev/null; then
    echo "  OK: curl available"
else
    echo "FAIL: wget or curl required for downloads"
    ERRORS=$((ERRORS + 1))
fi

# unzip (for easy mode)
if ! command -v unzip &>/dev/null; then
    echo "WARN: unzip not found (needed for Easy Mode data extraction)"
fi

# RAM check
if [[ "$OSTYPE" == "darwin"* ]]; then
    RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    RAM_GB=$((RAM_BYTES / 1073741824))
elif [ -f /proc/meminfo ]; then
    RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    RAM_GB=$((RAM_KB / 1048576))
else
    RAM_GB=0
fi

if [ "$RAM_GB" -gt 0 ]; then
    if [ "$MODE" = "full" ] && [ "$RAM_GB" -lt 32 ]; then
        echo "WARN: ${RAM_GB}GB RAM detected. Full Mode recommends 32GB."
    elif [ "$MODE" = "easy" ] && [ "$RAM_GB" -lt 16 ]; then
        echo "WARN: ${RAM_GB}GB RAM detected. Easy Mode recommends 16GB."
    else
        echo "  OK: ${RAM_GB}GB RAM"
    fi
fi

# Disk space
AVAIL_GB=$(df -g . 2>/dev/null | tail -1 | awk '{print $4}' || echo 0)
if [ "$AVAIL_GB" -gt 0 ]; then
    if [ "$MODE" = "full" ] && [ "$AVAIL_GB" -lt 100 ]; then
        echo "WARN: ${AVAIL_GB}GB free disk. Full Mode needs ~100GB."
    elif [ "$MODE" = "easy" ] && [ "$AVAIL_GB" -lt 5 ]; then
        echo "WARN: ${AVAIL_GB}GB free disk. Easy Mode needs ~5GB."
    else
        echo "  OK: ${AVAIL_GB}GB free disk"
    fi
fi

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo "FAILED: $ERRORS critical issue(s). Fix them before running the pipeline."
    exit 1
fi

echo ""
echo "All checks passed."
