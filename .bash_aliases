# Description: This file contains aliases and functions to be used as commands in the terminal.

# Sources the setup.bash file for ROS2 Humble.
alias shumble='source /opt/ros/humble/setup.bash'
# Sources the setup.bash file for ROS2 Iron.
alias siron='source /opt/ros/iron/setup.bash'
# Sources the install/setup.bash file for the current ROS2 workspace.
alias si='source install/setup.bash'
# This alias sets up the conda environment by initializing conda and adding it to the PATH.
alias conda_setup="
    # >>> conda initialize >>>
    # !! Contents within this block are managed by 'conda init' !!
    __conda_setup="$('/home/ekberndt/anaconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
    eval "$__conda_setup"
    else
    if [ -f "/home/ekberndt/anaconda3/etc/profile.d/conda.sh" ]; then
            . "/home/ekberndt/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/ekberndt/anaconda3/bin:$PATH"
    fi
    fi
    unset __conda_setup
    # <<< conda initialize <<<
"
# Function: cuda
# Description: Sets the environment variables required for using a specific version of the CUDA toolkit.
# Parameters:
#   $1 - CUDA version number
# Usage: cuda <version_number>
cuda() {
    # Remove any existing CUDA paths from the PATH variable
    PATH=$(echo "$PATH" | awk -v RS=: -v ORS=: '/cuda/ {next} {print}' | sed 's/:$//')
    # Remove any existing CUDA paths from the LD_LIBRARY_PATH variable
    LD_LIBRARY_PATH=$(echo "$LD_LIBRARY_PATH" | awk -v RS=: -v ORS=: '/cuda/ {next} {print}' | sed 's/:$//')

    # Set the environment variables for the specified CUDA version
    export PATH=/usr/local/cuda-$1/bin:$PATH
    export LD_LIBRARY_PATH=/usr/local/cuda-$1/lib64:$LD_LIBRARY_PATH
    export CUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda-$1
    # Env Variables for CMAKE
    export CUDA_HOME=/usr/local/cuda-$1


    # Display the CUDA version
    nvcc --version
}

# Function: sys_monitor
# Description: Script to bringup nvtop and htop to view system resources
# Parameters: None
# Usage: sys_monitor
sys_monitor() {
    DIR="~"
    # Only run this function if tmux if the session doesn't exist
    if ! tmux has-session -t sys_monitor; then
        # Create a new session called sys_monitor
        echo "Creating new tmux session: sys_monitor"
        tmux new-session -s sys_monitor -n sys_monitor -d -c $DIR

        # Split the window into 2 panes
        tmux split-window -v -t sys_monitor:0.0 -c $DIR
        tmux select-layout -t sys_monitor:0.0 even-horizontal
        tmux select-pane -t sys_monitor:0.0

        # Open nvtop in the first pane
        tmux send-keys -t sys_monitor:0.0 'nvtop' C-m
        # Open htop in the second pane
        tmux send-keys -t sys_monitor:0.1 'htop' C-m

        # Attach to the session
        tmux attach -t sys_monitor
    else
        echo "Session already exists: sys_monitor"
    fi
}

