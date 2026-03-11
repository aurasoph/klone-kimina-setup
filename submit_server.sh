#!/bin/bash
# submit_server.sh

set -a
source .env
set +a

if ["$HYAK_USERNAME" == ""]; then HYAK_USERNAME="$USER"; fi

sbatch --cpus-per-task=$JOB_CPUS \
       --mem=$JOB_MEM \
       --time=$JOB_TIME \
       --partition=cpu-g2 \
       --account=amath \
       run_kimina.slurm