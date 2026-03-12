import os
import glob
from dotenv import load_dotenv
from kimina_client import KiminaClient

load_dotenv()

def get_discovery_path():
    user = os.getenv("HYAK_USERNAME")
    if user == "":
        user = os.getenv("USER")
    folder = os.getenv("DISCOVERY_FOLDER_NAME")
    return f"/mmfs1/gscratch/scrubbed/{user}/{folder}"

def get_url():
    discovery_dir = get_discovery_path()
    addr_files = glob.glob(f"{discovery_dir}/*.addr")
    if not addr_files:
        raise RuntimeError(f"No active Kimina servers found in {discovery_dir}!")
    with open(addr_files[0], 'r') as f:
        return f.read().strip()

if __name__ == "__main__":
    client = KiminaClient(get_url())

    proof = "theorem my_theorem (p q : Prop) : p ∧ q ↔ q ∧ p := by exact And.comm"
    timeout = os.getenv("TIMEOUT")
    result = client.check(proof, timeout=timeout)

    print(f"Verification Results for: {client.api_url}")
    print(result.model_dump_json(indent=2))