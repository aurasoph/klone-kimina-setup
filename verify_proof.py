import os
import glob
from dotenv import load_dotenv
from kimina_client import KiminaClient

load_dotenv()

def get_discovery_path():
    user = os.getenv("HYAK_USERNAME")
    if not user:
        user = os.getenv("USER")
    folder = os.getenv("DISCOVERY_FOLDER_NAME")
    scratch_base = os.getenv("SCRATCH_BASE", "/mmfs1/gscratch/scrubbed")
    return f"{scratch_base}/{user}/{folder}"

def get_url():
    # KIMINA_SERVER_URL bypasses discovery — set this on hosts that can't
    # see the klone gscratch filesystem (e.g. tillicum) and point it at the
    # cloudflared URL printed in the SLURM log.
    env_url = os.getenv("KIMINA_SERVER_URL")
    if env_url:
        return env_url.strip()
    discovery_dir = get_discovery_path()
    addr_files = glob.glob(f"{discovery_dir}/*.addr")
    if not addr_files:
        raise RuntimeError(f"No active Kimina servers found in {discovery_dir}!")
    with open(addr_files[0], 'r') as f:
        return f.read().strip()

if __name__ == "__main__":
    client = KiminaClient(get_url())

    proof = "theorem my_theorem (p q : Prop) : p ∧ q ↔ q ∧ p := by exact And.comm"
    timeout_val = os.getenv("TIMEOUT", "60")
    
    result = client.check(proof, timeout=float(timeout_val), reuse=False)

    print(f"Verification Results for: {client.api_url}")
    print(result.model_dump_json(indent=2))
