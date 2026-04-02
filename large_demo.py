import sys
import os
import glob
from dotenv import load_dotenv

# --- System Setup ---
USER = os.getenv("HYAK_USERNAME") or os.getenv("USER") or os.getlogin()
SCRATCH = f"/mmfs1/gscratch/scrubbed/{USER}"

ENGINE_ROOT = os.path.join(SCRATCH, "kimina-engine")
DISCOVERY_PATH = os.path.join(SCRATCH, "kimina_server_discovery", "*.addr")

if ENGINE_ROOT not in sys.path:
    sys.path.insert(0, ENGINE_ROOT)

from kimina_client.sync_client import KiminaClient
from kimina_client.infotree import extract_data
from server.split import split_snippet

def get_server_url():
    with open(glob.glob(DISCOVERY_PATH)[0], 'r') as f:
        return f.read().strip()

client = KiminaClient(get_server_url())

# --- Demo 1: Verification ---
def run_verification():
    print(f"\n{' DEMO 1: VERIFICATION ':=^60}")
    
    codes = [
        {"id": "valid", "code": "theorem t1 (n : Nat) : n + 0 = n := by rfl"},
        {"id": "invalid", "code": "theorem t2 : 2 + 2 = 5 := by rfl"}
    ]
    
    response = client.check(codes, timeout=30, reuse=False)
    
    for res in response.results:
        data = res.model_dump()
        repl = data.get('response') or {}
        # A human dev uses .get() because Lean omits 'messages' if the code is perfect
        messages = repl.get('messages', [])
        is_valid = not any(m['severity'] == 'error' for m in messages)
        print(f"ID: {data['id']:<10} | {'✅ VALID' if is_valid else '❌ INVALID'}")


# --- Demo 2: Extraction ---
def run_extraction():
    print(f"\n{' DEMO 2: EXTRACTION ':=^60}")
    
    lean_code = """
import Mathlib
theorem demo_ex (n : Nat) : n + 0 = n := by
  induction n with
  | zero => rfl
  | succ n ih => simp [ih]
"""
    response = client.check(
        [{"id": "ex", "code": lean_code}],
        timeout=300,
        reuse=False,
        infotree="original",
    )
    res = response.results[0].model_dump().get('response') or {}

    split = split_snippet(lean_code)
    intervals = extract_data(res.get('infotree', []), split.body)
    
    for i, step in enumerate(intervals, 1):
        tactic = step['tactic'].strip().replace('\n', ' ')
        goal = step['goalsBefore'][0] if step['goalsBefore'] else "Solved"
        print(f"\n[Step {i}]: {tactic}\nSTATE:\n{goal}\n{'-'*40}")


# --- Demo 3: Error Discovery ---
def run_error_demo():
    print(f"\n{' DEMO 3: ERROR STATE ':=^60}")
    
    lean_code = """
import Mathlib
theorem error_test (n : Nat) : n + 1 = 1 + n := by
  induction n with
  | zero => rfl
  | succ n ih => 
    rw [Nat.add_assoc]
"""
    response = client.check(
        [{"id": "err", "code": lean_code}],
        timeout=300,
        reuse=False,
        infotree="original",
    )
    res = response.results[0].model_dump().get('response') or {}
    
    # We expect an error here, so we grab the first one we find
    messages = res.get('messages', [])
    error = [m for m in messages if m['severity'] == 'error'][0]
    print(f"Error on Line {error['pos']['line']}: {error['data'].splitlines()[0]}")

    split = split_snippet(lean_code)
    intervals = extract_data(res.get('infotree', []), split.body)
    error = intervals[-1]

    print(f"\n{' ERROR GOAL ':-^40}")
    print(error['goalsBefore'][0])
    print(f"{'-'*40}")
    print(f"Failing Tactic: {error['tactic'].strip()}")


if __name__ == "__main__":
    load_dotenv()
    run_verification()
    run_extraction()
    run_error_demo()