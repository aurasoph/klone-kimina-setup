#!/bin/bash
#SBATCH --nodes=1
#SBATCH --output=kimina_server_%j.log
#SBATCH --error=kimina_server_%j.err

set -a
source ".env"
set +a

if [ "$HYAK_USERNAME" == "" ]; then HYAK_USERNAME="$USER"; fi

SCRATCH_BASE="${SCRATCH_BASE:-/mmfs1/gscratch/scrubbed}"
G_BASE="${SCRATCH_BASE}/${HYAK_USERNAME}"
KIMINA_ENGINE_DIR="${G_BASE}/${ENGINE_FOLDER_NAME}"
DISCOVERY_DIR="${G_BASE}/${DISCOVERY_FOLDER_NAME}"
KIMINA_IMAGE="${KIMINA_ENGINE_DIR}/kimina-lean-server.sif"

NODE_NAME=$(hostname)

# Ask the kernel for a free ephemeral port instead of blindly picking a
# random one in [10000,65000) — klone compute nodes are shared and a blind
# pick collides occasionally, killing Kimina with EADDRINUSE.
pick_free_port() {
    python3 -c 'import socket
s = socket.socket()
s.bind(("0.0.0.0", 0))
print(s.getsockname()[1])
s.close()'
}
PORT=$(pick_free_port)
if [[ -z "$PORT" ]]; then
    echo "Failed to allocate a free port" >&2
    exit 1
fi
ADDR_FILE="${DISCOVERY_DIR}/${NODE_NAME}.addr"
TUNNEL_URL_FILE="${DISCOVERY_DIR}/${NODE_NAME}.tunnel"
CLOUDFLARED_LOG="${DISCOVERY_DIR}/${NODE_NAME}.cloudflared.log"

mkdir -p "$DISCOVERY_DIR"
echo "http://${NODE_NAME}:${PORT}" > "$ADDR_FILE"

cleanup() {
    rm -f "$ADDR_FILE" "$TUNNEL_URL_FILE"
    [[ -n "${CFD_PID:-}" ]] && kill "$CFD_PID" 2>/dev/null || true
}
trap cleanup EXIT

if [ ! -f "$KIMINA_IMAGE" ]; then
  echo "Kimina image not found: $KIMINA_IMAGE" >&2
  exit 1
fi

# Run Kimina in the background so this script can supervise the tunnel too.
# Binding the host source tree over /root/kimina-lean-server masks the
# container's bundled mathlib4 workspace and compiled repl binary, which
# causes Lean subprocess startup to fail — so we deliberately don't bind it.
apptainer exec \
  --pwd /root/kimina-lean-server \
  --env ELAN_HOME=/root/.elan \
  --env LEAN_SERVER_HOST=0.0.0.0 \
  --env LEAN_SERVER_PORT=$PORT \
  --env LEAN_SERVER_LEAN_VERSION=$LEAN_VERSION \
  --env LEAN_SERVER_MAX_REPL_MEM=$MAX_REPL_MEM \
  --env LEAN_SERVER_MAX_WAIT=$TIMEOUT \
  "$KIMINA_IMAGE" python -m server &
KIMINA_PID=$!

# Wait for Kimina to bind the port (local check via 127.0.0.1 avoids the
# klone Squid proxy that intercepts hostname-based requests).
echo "Waiting for Kimina to bind 127.0.0.1:${PORT}..."
for i in $(seq 1 60); do
    if curl -s --max-time 2 --output /dev/null "http://127.0.0.1:${PORT}/health"; then
        echo "Kimina healthy."
        break
    fi
    if ! kill -0 "$KIMINA_PID" 2>/dev/null; then
        echo "Kimina exited before becoming healthy." >&2
        exit 1
    fi
    sleep 5
done

if ! curl -s --max-time 2 --output /dev/null "http://127.0.0.1:${PORT}/health"; then
    echo "Kimina did not become healthy in 5 minutes." >&2
    kill "$KIMINA_PID" 2>/dev/null
    exit 1
fi

# Launch cloudflared.
# --protocol http2 forces TCP — klone's egress firewall blocks outbound UDP
# (default QUIC), which would otherwise silently fail and retry forever.
CLOUDFLARED_BIN="${HOME}/.local/bin/cloudflared"
if [ ! -x "$CLOUDFLARED_BIN" ]; then
    echo "cloudflared not found at $CLOUDFLARED_BIN — install with:" >&2
    echo "  curl -fsSL -o ~/.local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x ~/.local/bin/cloudflared" >&2
    kill "$KIMINA_PID" 2>/dev/null
    exit 1
fi

"$CLOUDFLARED_BIN" tunnel --url "http://127.0.0.1:${PORT}" --protocol http2 --no-autoupdate > "$CLOUDFLARED_LOG" 2>&1 &
CFD_PID=$!

# Wait for cloudflared to publish the trycloudflare URL.
echo "Waiting for cloudflared URL..."
TUNNEL_URL=""
for i in $(seq 1 60); do
    if grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$CLOUDFLARED_LOG" 2>/dev/null | head -1 > /tmp/tunnel_url.$$; then
        TUNNEL_URL=$(cat /tmp/tunnel_url.$$)
        rm -f /tmp/tunnel_url.$$
        if [ -n "$TUNNEL_URL" ]; then break; fi
    fi
    sleep 2
done

if [ -z "$TUNNEL_URL" ]; then
    echo "cloudflared did not publish a URL in 2 minutes. Tail of its log:" >&2
    tail -30 "$CLOUDFLARED_LOG" >&2
    kill "$KIMINA_PID" "$CFD_PID" 2>/dev/null
    exit 1
fi

echo "$TUNNEL_URL" > "$TUNNEL_URL_FILE"

cat <<BANNER
============================================================
  KIMINA_TUNNEL_URL=$TUNNEL_URL
  (local: http://${NODE_NAME}:${PORT})
  (also written to: $TUNNEL_URL_FILE)
============================================================
BANNER

# Hand control back to Kimina (foreground). The trap on EXIT will tear
# down cloudflared when Kimina exits (either by walltime or by error).
wait "$KIMINA_PID"
