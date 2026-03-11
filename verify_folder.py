import os
import glob
import sys
import time
from dotenv import load_dotenv
from kimina_client import KiminaClient

# Load configuration from the .env file
load_dotenv()

def get_discovery_path():
    """Constructs the discovery path dynamically based on the project environment."""
    user = os.getenv("HYAK_USERNAME")
    folder = os.getenv("DISCOVERY_FOLDER_NAME")
    return f"/mmfs1/gscratch/scrubbed/{user}/{folder}"

def get_url():
    """Retrieves the active server address from the discovery directory."""
    discovery_dir = get_discovery_path()
    addr_files = glob.glob(f"{discovery_dir}/*.addr")
    if not addr_files:
        raise RuntimeError(f"No active Kimina servers found in {discovery_dir}!")
    with open(addr_files[0], 'r') as f:
        return f.read().strip()

def run_lean_folder(folder_path, chunk_size=10):
    """
    Identifies all .lean files and processes them in safe 'chunks' to prevent 
    network timeouts and payload errors while utilizing server-side parallelization.
    """
    client = KiminaClient(get_url())
    lean_files = sorted(glob.glob(os.path.join(folder_path, "*.lean")))
    
    if not lean_files:
        print(f"No .lean files found in directory: {folder_path}")
        return

    file_data = []
    for f_path in lean_files:
        with open(f_path, 'r') as f:
            file_data.append({
                "name": os.path.basename(f_path),
                "content": f.read()
            })

    total_files = len(file_data)
    print(f"Processing {total_files} files in chunks of {chunk_size}...")
    
    all_results = []
    start_time = time.time()

    for i in range(0, total_files, chunk_size):
        chunk = file_data[i : i + chunk_size]
        chunk_contents = [item["content"] for item in chunk]
        chunk_names = [item["name"] for item in chunk]
        
        print(f"[{i+len(chunk)}/{total_files}] Submitting batch...")
        
        batch_result = client.check(chunk_contents)
        
        for name, res in zip(chunk_names, batch_result.results):
            all_results.append({
                "name": name,
                "status": res.analyze().status,
                "time": res.time
            })

    # Final Summary Table
    print("\n" + "="*75)
    print(f"{'FILE NAME':<45} | {'STATUS':<12} | {'TIME'}")
    print("-" * 75)
    
    for res in all_results:
        print(f"{res['name']:<45} | {res['status']:<12} | {res['time']:.2f}s")

    print(f"\nTotal Processing Time: {time.time() - start_time:.2f}s")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python run_folder.py <folder_path>")
    else:
        target_dir = sys.argv[1]
        if os.path.isdir(target_dir):
            # A chunk_size of 10-20 is generally safe for most network conditions
            run_lean_folder(target_dir, chunk_size=10)
        else:
            print(f"Error: {target_dir} is not a valid directory.")