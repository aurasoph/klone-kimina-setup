# Kimina Lean Server — Cross-Cluster Setup (klone + tillicum)

Run the [Kimina Lean Server](https://github.com/project-numina/kimina-lean-server) on **klone** and reach it from **tillicum** (or any other client) without any inbound network exposure or shared filesystem.

The server runs inside an apptainer container on a klone compute node, opens an outbound [Cloudflare Quick Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/trycloudflare/), and prints a `*.trycloudflare.com` URL into its SLURM log. Any client with that URL can POST proofs to it over plain HTTPS.

```
   tillicum compute node                 klone compute node
   ┌────────────────────┐                ┌─────────────────────────────┐
   │ verify_proof.py    │                │ kimina-lean-server (sif)    │
   │ KiminaClient ──────┼─ HTTPS ─┐      │ uvicorn :PORT (loopback)    │
   └────────────────────┘         │      │      ▲                      │
                                  ▼      │      │  forward             │
                          ┌────────────────────────┐                   │
                          │  Cloudflare edge       │                   │
                          │  *.trycloudflare.com   │◀── HTTP/2 tunnel ─┤
                          └────────────────────────┘  (outbound from   │
                                                       cloudflared)    │
                                                                       │
                                                       └───────────────┘
```

Both sides only need **outbound** HTTPS. Nobody has to forward a port, run an SSH tunnel, or trust each other's auth.

---

## Prerequisites

- A UW NetID with access to both **klone** and **tillicum** (`ssh <netid>@klone.hyak.uw.edu` and `ssh <netid>@tillicum.hyak.uw.edu`).
- Duo 2FA enrolled on each cluster (UW's standard).
- A scratch quota on klone (`/mmfs1/gscratch/scrubbed/<netid>` by default) — the container image alone is ~5 GB.
- A project quota on tillicum where you can create a conda env.

> This branch (`cross-cluster`) targets two-cluster usage. For the single-cluster (klone-only) workflow, use `main`.

---

## 1. Klone side: install and launch the server

### 1a. Clone and configure

```bash
ssh <netid>@klone.hyak.uw.edu
cd /mmfs1/gscratch/scrubbed/<netid>
git clone -b cross-cluster https://github.com/aurasoph/klone-kimina-setup.git
cd klone-kimina-setup
```

Edit `.env` — at minimum set `HYAK_USERNAME=<your netid>`. The defaults for resources (`JOB_CPUS=16`, `JOB_MEM=32G`, `JOB_TIME=08:00:00`, `JOB_ACCOUNT=stf`, `JOB_PARTITION=cpu-g2`) are reasonable starting points; adjust if your account/allocation differs.

### 1b. One-time install
Please allocate yourself a compute node for this step 
```bash
bash install.sh
```

This:
1. Sets up scratch-local caches for elan/conda/apptainer.
2. Downloads `cloudflared` to `~/.local/bin/cloudflared`.
3. Pulls the `kimina-lean-server:2.0.0` container image (`~30 min` first time).
4. Builds Lean/mathlib inside the container.
5. Creates a conda env at `${PROJECT_FOLDER_NAME}/conda_env`.
6. Copies scripts and example files into the project dir.

Run it from a compute node, not the login node — `salloc --time=02:00:00 --mem=10G --cpus-per-task=1` is enough.

### 1c. Submit the server job

```bash
cd /mmfs1/gscratch/scrubbed/<netid>/${PROJECT_FOLDER_NAME:-kimina_example_project}
./submit_server.sh
```

`submit_server.sh` reads resource settings from `.env` and submits `run_kimina.slurm`. The job:
1. Picks a free port via `socket.bind(("",0))` and starts Kimina bound to `0.0.0.0:<port>`.
2. Waits for `/health` to be live on `127.0.0.1:<port>`.
3. Starts `cloudflared tunnel --url http://127.0.0.1:<port> --protocol http2` (HTTP/2 is required — klone's egress firewall drops UDP/QUIC).
4. Parses the assigned `*.trycloudflare.com` URL out of cloudflared's log.
5. Prints a banner with that URL into the SLURM log and writes it to `${DISCOVERY_FOLDER_NAME}/<node>.tunnel`.

### 1d. Find the tunnel URL

```bash
grep KIMINA_TUNNEL_URL kimina_server_<jobid>.log
```

Example output:
```
KIMINA_TUNNEL_URL=https://wallet-dated-rom-chairman.trycloudflare.com
```

That URL is valid until the SLURM job exits. Copy it.

---

## 2. Tillicum side: install and run the client

### 2a. Clone and install

```bash
ssh <netid>@tillicum.hyak.uw.edu
cd /gpfs/projects/<your-group>/<netid>   # or wherever you have quota
git clone -b cross-cluster https://github.com/aurasoph/klone-kimina-setup.git
cd klone-kimina-setup
./install_client.sh
```

This creates `./conda_env` with Python 3.10, `kimina-client`, and `python-dotenv`. (`kimina-client` requires 3.10+ due to PEP 604 type unions.)

### 2b. Activate and point at the tunnel

```bash
module load conda
conda activate ./conda_env
export KIMINA_SERVER_URL=https://wallet-dated-rom-chairman.trycloudflare.com   # paste the URL from §1d
```

### 2c. Send a proof

Single proof:
```bash
python verify_proof.py
```

A folder of `.lean` files:
```bash
python verify_folder.py example_lean
```

Larger demo (verification + infotree extraction + intentional error):
```bash
python large_demo.py
```

All three scripts check `KIMINA_SERVER_URL` first; if unset they fall back to discovery files on the local scratch filesystem (the single-cluster workflow on `main`).

---

## What the SLURM job actually does

`run_kimina.slurm` is the supervisor that keeps Kimina and `cloudflared` glued together for the life of the job. Read the file for the details — it's short and commented. Two things worth flagging:

- **Port selection** uses Python's `socket.bind(("",0))` to ask the kernel for a free ephemeral port. A blind `shuf` random pick collides occasionally on shared compute nodes (you'll see `[Errno 98] Address already in use` and Kimina dies on startup).
- **`--protocol http2`** is mandatory for `cloudflared` on klone. The default QUIC transport uses UDP, which klone's egress firewall drops; QUIC just retries forever and never produces a URL.

---

## Caveats and limits

- **The Quick Tunnel URL is public.** Anyone who learns the `*.trycloudflare.com` hostname can POST proofs to your server. The hostname is high-entropy and not indexed anywhere, so it's "security by obscurity" — fine for a research POC, not for anything sensitive or long-lived.
- **TLS terminates at Cloudflare.** Request bodies are visible to Cloudflare's edge.
- **Quick Tunnels are unsupported / for testing.** Per Cloudflare's docs they have no SLA and can be rate-limited or removed at any time. For a 24/7 production setup, replace `cloudflared tunnel --url …` with a [Named Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/create-remote-tunnel/) under a real Cloudflare account, which gives you a stable hostname and access controls.
- **Ephemeral.** The hostname changes every SLURM job. The client has to be told the new URL each time (`export KIMINA_SERVER_URL=…`).
- **Walltime ends the tunnel.** Set `JOB_TIME` to match how long you actually need the server. If the job is preempted (`stf-ckpt`, `ckpt-all`), the tunnel dies with it.

---

## Troubleshooting

- **`Address already in use` on Kimina startup** — a stray process on the shared node took your port between selection and bind. Resubmit; the retry chooses a new port.
- **`cloudflared did not publish a URL in 2 minutes`** — usually a transient Cloudflare edge issue or a temporary outbound block. Check the tail of `<node>.cloudflared.log` in the discovery dir for the actual error.
- **`Permission denied (gssapi-keyex,gssapi-with-mic,keyboard-interactive)`** when SSHing to either cluster — Duo isn't being prompted because your client has no TTY. Use a normal interactive SSH (`ssh <netid>@…`) the first time to seat any ControlMaster.
- **`RuntimeError: No active Kimina servers found in …`** on the client — you forgot to `export KIMINA_SERVER_URL`. The scripts fall back to filesystem discovery when the env var is unset.

---

## Layout

| File | Side | Purpose |
| --- | --- | --- |
| `install.sh` | klone | One-time setup: caches, cloudflared, container, conda, Lean build |
| `install_client.sh` | tillicum | One-time setup: conda env with `kimina_client` |
| `run_kimina.slurm` | klone | SLURM job that runs Kimina + cloudflared |
| `submit_server.sh` | klone | Wrapper that injects resource args from `.env` |
| `verify_proof.py` | client | Single-theorem smoke test |
| `verify_folder.py` | client | Batch-verifies every `.lean` in a folder |
| `large_demo.py` | client | Verification + infotree extraction + error demo |
| `.env` | both (mostly klone) | Cluster / job / Lean config |
| `example_lean/` | client | Sample `.lean` files for `verify_folder.py` |
