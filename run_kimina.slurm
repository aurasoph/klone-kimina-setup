#!/bin/bash
#SBATCH --nodes=1
#SBATCH --output=kimina_server_%j.log

set -a
source .env
set +a

G_BASE="/mmfs1/gscratch/scrubbed/${HYAK_USERNAME}"
KIMINA_ENGINE_DIR="${G_BASE}/${ENGINE_FOLDER_NAME}"
DISCOVERY_DIR="${G_BASE}/${DISCOVERY_FOLDER_NAME}"

NODE_NAME=$(hostname)
PORT=$(shuf -i 10000-65000 -n 1)
ADDR_FILE="${DISCOVERY_DIR}/${NODE_NAME}.addr"

mkdir -p "$DISCOVERY_DIR"
echo "http://${NODE_NAME}:${PORT}" > "$ADDR_FILE"
trap 'rm -f "$ADDR_FILE"' EXIT

apptainer exec \
  --bind "${KIMINA_ENGINE_DIR}:/root/kimina-lean-server" \
  --pwd /root/kimina-lean-server \
  --env LEAN_SERVER_HOST=0.0.0.0 \
  --env LEAN_SERVER_PORT=$PORT \
  --env LEAN_SERVER_LEAN_VERSION=$LEAN_VERSION \
  --env LEAN_SERVER_MAX_REPL_MEM=$MAX_REPL_MEM \
  "${KIMINA_ENGINE_DIR}/kimina-lean-server.sif" python -m server