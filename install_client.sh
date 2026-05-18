#!/bin/bash
# install_client.sh — tillicum-side install. Creates a conda env in
# ./conda_env with kimina_client + python-dotenv. No apptainer, no engine
# clone — the server runs on klone and is reached over a Cloudflare tunnel.
#
# Run this once from the cloned klone-kimina-setup directory on tillicum.

set -euo pipefail

if ! command -v module >/dev/null 2>&1; then
    echo "ERROR: 'module' command not found. Are you on a UW Hyak login node?" >&2
    exit 1
fi

module load conda

CONDA_ENV="$(pwd)/conda_env"

if [ ! -d "$CONDA_ENV" ]; then
    echo "--- Creating conda env at $CONDA_ENV (python 3.10) ---"
    conda create --prefix "$CONDA_ENV" python=3.10 -y
fi

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$CONDA_ENV"

echo "--- Installing kimina_client + python-dotenv ---"
pip install --upgrade pip

# kimina_client lives inside the kimina-lean-server repo. The PyPI name has
# historically lagged behind, so install straight from the upstream repo.
pip install "git+https://github.com/project-numina/kimina-lean-server.git"
pip install python-dotenv

echo "--------------------------------------------------------"
echo "Client install complete. To use:"
echo ""
echo "  conda activate $CONDA_ENV"
echo "  export KIMINA_SERVER_URL=https://<...>.trycloudflare.com"
echo "  python verify_proof.py"
echo "--------------------------------------------------------"
