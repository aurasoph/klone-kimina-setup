#!/bin/bash
#SBATCH --nodes=1
#SBATCH --gpus 1
#SBATCH --cpus-per-gpu 4
#SBATCH --time=00:05:00
#SBATCH --output=kimina_client_%j.log
#SBATCH --error=kimina_client_%j.err

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

set -a
source ".env"
set +a

if [ "$HYAK_USERNAME" == "" ]; then HYAK_USERNAME="$USER"; fi

SCRATCH_BASE="${SCRATCH_BASE:-/mmfs1/gscratch/scrubbed}"
G_BASE="${SCRATCH_BASE}/${HYAK_USERNAME}"
USER_PROJECT_DIR="${G_BASE}/${PROJECT_FOLDER_NAME}"
DISCOVERY_DIR="${G_BASE}/${DISCOVERY_FOLDER_NAME}"

# Activate the conda environment created by install.sh
# module load conda
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "${USER_PROJECT_DIR}/conda_env"

# Wait for a discovery file to appear and for /health to return 2xx.
# The addr file is re-read every iteration so that a server restart (which
# removes the old file and writes a new one) is picked up automatically.
# Connection refused (curl exit 7) means the port isn't bound yet — we go
# back to the top of the loop rather than counting it as a health failure.
echo "Waiting for server to become healthy (${DISCOVERY_DIR})..."
SERVER_URL=""
HEALTHY=0
for i in $(seq 1 120); do
    mapfile -t addr_files < <(compgen -G "${DISCOVERY_DIR}/*.addr" 2>/dev/null || true)
    if [[ ${#addr_files[@]} -eq 0 || ! -f "${addr_files[0]}" ]]; then
        echo "  [${i}/120] No discovery file yet, waiting..."
        sleep 10
        continue
    fi

    SERVER_URL=$(cat "${addr_files[0]}")

    curl_rc=0
    curl --silent --fail --max-time 5 --output /dev/null "${SERVER_URL}/health" \
        || curl_rc=$?

    if [[ $curl_rc -eq 0 ]]; then
        echo "Server is healthy at ${SERVER_URL}"
        HEALTHY=1
        break
    elif [[ $curl_rc -eq 7 ]]; then
        echo "  [${i}/120] Connection refused — server is binding port, waiting..."
    else
        echo "  [${i}/120] Not yet healthy (curl exit ${curl_rc}), retrying..."
    fi
    sleep 10
done

if [[ $HEALTHY -eq 0 ]]; then
    echo "ERROR: Server did not become healthy after 20 minutes." >&2
    exit 1
fi

# Run verify_folder.py, retrying every 10s on connection errors (exit 1).
echo ""
echo "=== Running verification tests against ${SCRIPT_DIR}/example_lean ==="
while true; do
    if python verify_folder.py example_lean; then
        break
    fi
    echo "Connection error from server, retrying in 10s..."
    sleep 10
done
