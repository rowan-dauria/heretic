#!/bin/bash
#!
#! SLURM job script for running heretic on Qwen/Qwen3-4B (Wilkes3)
#!

#!#############################################################
#!#### Modify the options in this section as appropriate ######
#!#############################################################

#! sbatch directives begin here ###############################
#! Name of the job:
#SBATCH -J heretic-qwen3-4b
#! Which project should be charged (NB Wilkes2 projects end in '-GPU'):
#SBATCH -A MPHIL-DIS-SL2-GPU
#! How many whole nodes should be allocated?
#SBATCH --nodes=1
#! How many (MPI) tasks will there be in total?
#SBATCH --ntasks=1
#! Specify the number of GPUs per node (between 1 and 4; must be 4 if nodes>1).
#SBATCH --gres=gpu:1
#! How much wallclock time will be required?
#SBATCH --time=03:00:00
#! What types of email messages do you wish to receive?
#SBATCH --mail-type=NONE
#! Output files:
#SBATCH -o /home/rd761/heretic-fork/slurm_logs/slurm_%j.out
#SBATCH -e /home/rd761/heretic-fork/slurm_logs/slurm_%j.err
#! Uncomment this to prevent the job from being requeued (e.g. if
#! interrupted by node failure or system downtime):
##SBATCH --no-requeue

#! Do not change:
#SBATCH -p ampere

#! sbatch directives end here (put any additional directives above this line)
set -euo pipefail

#! Notes:
#! Charging is determined by GPU number*walltime.

#! Number of nodes and tasks per node allocated by SLURM (do not change):
numnodes=$SLURM_JOB_NUM_NODES
numtasks=$SLURM_NTASKS
mpi_tasks_per_node=$(echo "$SLURM_TASKS_PER_NODE" | sed -e  's/^\([0-9][0-9]*\).*$/\1/')
#! ############################################################
#! Modify the settings below to specify the application's environment, location
#! and launch method:

#! Optionally modify the environment seen by the application
#! (note that SLURM reproduces the environment at submission irrespective of ~/.bashrc):
. /etc/profile.d/modules.sh                # Leave this line (enables the module command)
module purge                               # Removes all modules still loaded
module load rhel8/default-amp              # REQUIRED - loads the basic environment

#! Insert additional module load commands after this line if needed:

#! Add uv to PATH:
export PATH="/home/rd761/.local/bin:$PATH"

#! Work directory (i.e. where the job will run):
workdir="/home/rd761/heretic-fork"
venv="$workdir/.venv"
run_root="/home/rd761/rds/hpc-work/heretic-qwen3-4b"
model_id="Qwen/Qwen3-4B"
n_trials=200
protected_layers="[2,12,24,33]"

export OMP_NUM_THREADS=1
export HF_HOME="/rds/user/rd761/hpc-work/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"

###############################################################
### You should not have to change anything below this line ####
###############################################################

JOBID=$SLURM_JOB_ID
run_dir="$run_root/job_$JOBID"
checkpoint_dir="$run_dir/checkpoints"

mkdir -p "$checkpoint_dir" "$HF_HUB_CACHE"

cd "$workdir"
echo -e "Changed directory to `pwd`.\n"

echo -e "JobID: $JOBID\n======"
echo "Time: `date`"
echo "Running on master node: `hostname`"
echo "Current directory: `pwd`"
echo "Run directory: $run_dir"
echo "Checkpoint directory: $checkpoint_dir"
echo "HF_HOME: $HF_HOME"

if [ "$SLURM_JOB_NODELIST" ]; then
        #! Create a machine file:
        export NODEFILE=`generate_pbs_nodefile`
        cat $NODEFILE | uniq > machine.file.$JOBID
        echo -e "\nNodes allocated:\n================"
        echo `cat machine.file.$JOBID | sed -e 's/\..*$//g'`
fi

echo -e "\nnumtasks=$numtasks, numnodes=$numnodes, mpi_tasks_per_node=$mpi_tasks_per_node (OMP_NUM_THREADS=$OMP_NUM_THREADS)"

if [ ! -f "$venv/bin/activate" ]; then
        echo "ERROR: expected virtual environment at $venv"
        echo "Create it with:"
        echo "  cd $workdir"
        echo "  uv venv .venv --python 3.12"
        echo "  source .venv/bin/activate"
        echo "  uv pip install -e ."
        exit 1
fi

source "$venv/bin/activate"

if python -c "import hf_transfer" >/dev/null 2>&1; then
        export HF_HUB_ENABLE_HF_TRANSFER=1
else
        unset HF_HUB_ENABLE_HF_TRANSFER
fi

export HERETIC_EXCLUDED_MLP_ABLITERATION_LAYERS="$protected_layers"
export HERETIC_ENABLE_THINKING=false

CMD=(
        heretic
        --model "$model_id"
        --n-trials "$n_trials"
        --study-checkpoint-dir "$checkpoint_dir"
)

echo "Python: $(which python)"
python --version
echo "Heretic: $(which heretic)"
echo "Protected MLP abliteration layers: $HERETIC_EXCLUDED_MLP_ABLITERATION_LAYERS"
echo "HF_HUB_ENABLE_HF_TRANSFER: ${HF_HUB_ENABLE_HF_TRANSFER:-unset}"

echo -e "\nExecuting command:\n=================="
printf ' %q' "${CMD[@]}"
echo -e "\n"

"${CMD[@]}"
