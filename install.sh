#!/bin/bash
# install.sh

set -a
source .env
set +a

if ["$HYAK_USERNAME" == ""]; then HYAK_USERNAME="$USER"; fi

G_BASE="/mmfs1/gscratch/scrubbed/${HYAK_USERNAME}"
KIMINA_ENGINE_DIR="${G_BASE}/${ENGINE_FOLDER_NAME}"
USER_PROJECT_DIR="${G_BASE}/${PROJECT_FOLDER_NAME}"
DISCOVERY_DIR="${G_BASE}/${DISCOVERY_FOLDER_NAME}"

# Redirect Lean/Elan to gscratch
export ELAN_HOME="${G_BASE}/.elan"
export PATH="${ELAN_HOME}/bin:${PATH}"

# Setup Hyak Caches
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
echo "*This may take up to an hour*"
cd "$KIMINA_ENGINE_DIR"
apptainer pull --force kimina-lean-server.sif docker://projectnumina/kimina-lean-server:2.0.0

echo "--- Step 3: Building Lean Components ---"
apptainer exec \
  --bind .:/root/kimina-lean-server \
  --bind "${ELAN_HOME}:${ELAN_HOME}" \
  --env ELAN_HOME="${ELAN_HOME}" \
  --env PATH="${ELAN_HOME}/bin:/usr/local/bin:/usr/bin:/bin" \
  --env LEAN_SERVER_LEAN_VERSION="$LEAN_VERSION" \
  --pwd /root/kimina-lean-server \
  kimina-lean-server.sif bash -c "rm -f .env && bash setup.sh"
cd -

echo "--- Step 4: Preparing Conda Project ---"
mkdir -p "$USER_PROJECT_DIR"
module load conda
if [ ! -d "${USER_PROJECT_DIR}/conda_env" ]; then
    conda create --prefix "${USER_PROJECT_DIR}/conda_env" python=3.10 -y
fi
conda activate "${USER_PROJECT_DIR}/conda_env"

echo "--- Step 5: Installing Python Client ---"
pip install --upgrade pip
pip install -e "${KIMINA_ENGINE_DIR}"
pip install python-dotenv

echo "--- Step 6: Finalizing ---"
cp ../klone-kimina-setup/submit_server.sh "$USER_PROJECT_DIR/"
cp ../klone-kimina-setup/run_kimina.slurm "$USER_PROJECT_DIR/"
cp ../klone-kimina-setup/verify_proof.py "$USER_PROJECT_DIR/"
cp ../klone-kimina-setup/demo_tactics.py "$USER_PROJECT_DIR/"
cp ../klone-kimina-setup/demo_batch.py "$USER_PROJECT_DIR/"
cp ../klone-kimina-setup/verify_folder.py "$USER_PROJECT_DIR/"
cp ../klone-kimina-setup/.env "$USER_PROJECT_DIR/"
mv ../klone-kimina-setup/example_lean "$USER_PROJECT_DIR"/


chmod +x "${USER_PROJECT_DIR}/submit_server.sh"

echo "--------------------------------------------------------"
echo "Installation Complete"
echo "Project Path: ${USER_PROJECT_DIR}"
echo "To start the server, go to the project path and run: ./submit_server.sh"
echo "--------------------------------------------------------"