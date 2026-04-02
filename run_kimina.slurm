#!/bin/bash
#SBATCH --nodes=1
#SBATCH --output=kimina_server_%j.log
#SBATCH --error=kimina_server_%j.err

set -a
source .env
set +a

if [ "$HYAK_USERNAME" == "" ]; then HYAK_USERNAME="$USER"; fi

G_BASE="/mmfs1/gscratch/scrubbed/${HYAK_USERNAME}"
KIMINA_ENGINE_DIR="${G_BASE}/${ENGINE_FOLDER_NAME}"
DISCOVERY_DIR="${G_BASE}/${DISCOVERY_FOLDER_NAME}"
KIMINA_IMAGE="${KIMINA_ENGINE_DIR}/kimina-lean-server.sif"

NODE_NAME=$(hostname)
PORT=$(shuf -i 10000-65000 -n 1)
ADDR_FILE="${DISCOVERY_DIR}/${NODE_NAME}.addr"

mkdir -p "$DISCOVERY_DIR"
echo "http://${NODE_NAME}:${PORT}" > "$ADDR_FILE"
trap 'rm -f "$ADDR_FILE"' EXIT

if [ ! -f "$KIMINA_IMAGE" ]; then
  echo "Kimina image not found: $KIMINA_IMAGE" >&2
  exit 1
fi

# Run the image as built. Binding the host source tree over
# /root/kimina-lean-server masks the container's bundled mathlib4 workspace
# and compiled repl binary, which causes Lean subprocess startup to fail.
apptainer exec \
  --pwd /root/kimina-lean-server \
  --env LEAN_SERVER_HOST=0.0.0.0 \
  --env LEAN_SERVER_PORT=$PORT \
  --env LEAN_SERVER_LEAN_VERSION=$LEAN_VERSION \
  --env LEAN_SERVER_MAX_REPL_MEM=$MAX_REPL_MEM \
  --env LEAN_SERVER_MAX_WAIT=$TIMEOUT \
  "$KIMINA_IMAGE" python -m server
