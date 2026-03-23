#!/bin/bash
# install.sh

set -a
source .env
set +a

if [ "$HYAK_USERNAME" == "" ]; then HYAK_USERNAME="$USER"; fi

G_BASE="/mmfs1/gscratch/scrubbed/${HYAK_USERNAME}"
KIMINA_ENGINE_DIR="${G_BASE}/${ENGINE_FOLDER_NAME}"
USER_PROJECT_DIR="${G_BASE}/${PROJECT_FOLDER_NAME}"
DISCOVERY_DIR="${G_BASE}/${DISCOVERY_FOLDER_NAME}"

# Redirect Lean/Elan/Conda to gscratch
export ELAN_HOME="${G_BASE}/.elan"
export PATH="${ELAN_HOME}/bin:${PATH}"
export APPTAINER_CACHEDIR="${G_BASE}/.apptainer_cache"
export APPTAINER_TMPDIR="${G_BASE}/.apptainer_tmp"
export CONDA_PKGS_DIRS="${G_BASE}/.conda_cache"
export PIP_CACHE_DIR="${G_BASE}/.pip_cache"

mkdir -p "$DISCOVERY_DIR" "$ELAN_HOME" "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR" "$CONDA_PKGS_DIRS" "$PIP_CACHE_DIR"

echo "--- Step 1: Cloning Engine ---"
if [ ! -d "$KIMINA_ENGINE_DIR" ]; then
    git clone https://github.com/project-numina/kimina-lean-server.git "$KIMINA_ENGINE_DIR"
fi

echo "--- Step 2: Pulling Container ---"
cd "$KIMINA_ENGINE_DIR"
if [ ! -f kimina-lean-server.sif ]; then
    if [ -d "/scr" ]; then
        echo "Using local SSD (/scr) for faster container build..."
        export APPTAINER_TMPDIR="/scr"
    else
        echo "Local SSD not found, using gscratch..."
        export APPTAINER_TMPDIR="${G_BASE}/.apptainer_tmp"
    fi
    
    apptainer pull --force kimina-lean-server.sif docker://projectnumina/kimina-lean-server:2.0.0
fi

echo "--- Step 3: Building Lean Components ---"
apptainer exec \
  --bind .:/root/kimina-lean-server \
  --bind "${G_BASE}:${G_BASE}" \
  --home "${G_BASE}" \
  --env ELAN_HOME="${ELAN_HOME}" \
  --env PATH="${ELAN_HOME}/bin:/usr/local/bin:/usr/bin:/bin" \
  --env LEAN_SERVER_LEAN_VERSION="$LEAN_VERSION" \
  --pwd /root/kimina-lean-server \
  kimina-lean-server.sif bash -c "rm -f .env && bash setup.sh"
cd -

echo "--- Step 4: Preparing Conda Project ---"
mkdir -p "$USER_PROJECT_DIR"
module load conda

# Detection for corrupted cache/env
if [ -d "${USER_PROJECT_DIR}/conda_env" ] && [ ! -f "${USER_PROJECT_DIR}/conda_env/bin/pip" ]; then
    echo "Detected corrupted conda environment. Wiping cache and environment..."
    rm -rf "${USER_PROJECT_DIR}/conda_env"
    conda clean -afy
fi

if [ ! -d "${USER_PROJECT_DIR}/conda_env" ]; then
    conda create --prefix "${USER_PROJECT_DIR}/conda_env" python=3.10 -y
fi

source $(conda info --base)/etc/profile.d/conda.sh
conda activate "${USER_PROJECT_DIR}/conda_env"

echo "--- Step 5: Installing Python Client ---"
if command -v pip &> /dev/null; then
    pip install --upgrade pip
    pip install -e "${KIMINA_ENGINE_DIR}"
    pip install python-dotenv
else
    echo "ERROR: Manually run 'rm -rf ${CONDA_PKGS_DIRS}' and retry."
    exit 1
fi

echo "--- Step 6: Finalizing ---"
SETUP_DIR="$(pwd)"
cp "${SETUP_DIR}/submit_server.sh" "$USER_PROJECT_DIR/"
cp "${SETUP_DIR}/run_kimina.slurm" "$USER_PROJECT_DIR/"
cp "${SETUP_DIR}/verify_proof.py" "$USER_PROJECT_DIR/"
cp "${SETUP_DIR}/demo_tactics.py" "$USER_PROJECT_DIR/"
cp "${SETUP_DIR}/demo_batch.py" "$USER_PROJECT_DIR/"
cp "${SETUP_DIR}/verify_folder.py" "$USER_PROJECT_DIR/"
cp "${SETUP_DIR}/.env" "$USER_PROJECT_DIR/"

if [ -d "${SETUP_DIR}/example_lean" ]; then
    cp -r "${SETUP_DIR}/example_lean" "$USER_PROJECT_DIR/"
fi

chmod +x "${USER_PROJECT_DIR}/submit_server.sh"

echo "--------------------------------------------------------"
echo "Installation Complete at: ${USER_PROJECT_DIR}"
echo "--------------------------------------------------------"