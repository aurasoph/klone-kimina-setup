#!/bin/bash
# submit_server.sh

set -a
source .env
set +a

if ["$HYAK_USERNAME" == ""]; then HYAK_USERNAME="$USER"; fi

G_BASE="/mmfs1/gscratch/scrubbed/${HYAK_USERNAME}"
DISCOVERY_DIR="${G_BASE}/${DISCOVERY_FOLDER_NAME}"

# Clean up previous runs
echo "Cleaning up stale discovery files..."
rm -f "${DISCOVERY_DIR}"/*.addr

# Submit the new job
sbatch --cpus-per-task=$JOB_CPUS \
       --mem=$JOB_MEM \
       --time=$JOB_TIME \
       --account=$JOB_ACCOUNT \
       --partition=$JOB_PARTITION \
       run_kimina.slurm