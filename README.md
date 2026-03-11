# Kimina Lean Server Deployment (Hyak)

This repository provides a streamlined setup for running the [Kimina Lean Server](https://github.com/project-numina/kimina-lean-server) on Hyak. It utilizes Apptainer for the server environment and a local Conda environment for the client.

## Quick Start

### 1. Placement and Configuration
Ensure the project folder is located in your `gscratch` directory (usually `/gscratch/scrubbed/<your-net-id>`). Update the `.env` file with your `HYAK_USERNAME` and desired resource allocations. If `HYAK_USERNAME` is left empty, `USER` will be used instead.

### 2. Installation
Run the installation script from within the setup folder. This will clone the engine, build Lean components, create a Conda environment, and pull the required Apptainer container:

```bash
bash install.sh

```
Notes:
- You should not run this from a login node. 1 CPU and 10G of memory is sufficient.
- Even with sufficient compute, this will take a while. In particular, creating the `.sif` file may take ~30 minutes. 

### 3. Start the Server

Navigate to your project directory (defined as `PROJECT_FOLDER_NAME` in your `.env`) and submit the server job to SLURM.

```bash
./submit_server.sh

```

You can monitor the startup progress in the generated `kimina_server_*.log` file.

### 4. Verify the Connection

Activate the provided Conda environment and run the verification test:

```bash
python verify_proof.py

```
