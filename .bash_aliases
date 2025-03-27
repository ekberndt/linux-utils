# Description: This file contains aliases and functions to be used as commands in the terminal.

# Sources the setup.bash file for ROS2 Humble.
alias shumble='source /opt/ros/humble/setup.bash'
# Sources the setup.bash file for ROS2 Iron.
alias siron='source /opt/ros/iron/setup.bash'
# Sources the install/setup.bash file for the current ROS2 workspace.
alias si='source install/setup.bash'
# This alias sets up the conda environment by initializing conda
# TODO: Decide which version of the conda_setup alias to use
# alias conda_setup='eval "$(~/anaconda3/bin/conda shell.bash hook)"'
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

# -----------------------------------------------------------------------------
# Function: cuda
# Description: Sets the environment variables required for using a specific
#   version of the CUDA toolkit.
# Parameters:
#   $1 - CUDA version number
# Usage: cuda <version_number>
# Returns:
#   1 - if the specified CUDA version is not found in /usr/local/
# -----------------------------------------------------------------------------
cuda() {
    # Check the version exists in /usr/local/
    if [ ! -d /usr/local/cuda-$1 ]; then
        echo "CUDA-$1 not found in /usr/local/"
        return 1
    fi

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

# -----------------------------------------------------------------------------
# Function: tensorrt
# Description: Sets the environment variable required for using a specific
#   version of TensorRT (assuming the user installed it in ~/libs/ using the
#   tar package installer and not the deb package).
# Parameters:
#   $1 - TensorRT version number
# Usage: tensorrt <version_number>
# -----------------------------------------------------------------------------
tensorrt() {
    # Check the version exists in ~/libs/
    if [ ! -d ~/libs/TensorRT-$1 ]; then
        echo "TensorRT-$1 not found in ~/libs/"
        return 1
    fi

    # Remove any existing TensorRT paths from the LD_LIBRARY_PATH variable
    LD_LIBRARY_PATH=$(echo "$LD_LIBRARY_PATH" | awk -v RS=: -v ORS=: '/tensorrt/ {next} {print}' | sed 's/:$//')

    # Set the LD_LIBRARY_PATH variable for the specified TensorRT version
    export LD_LIBRARY_PATH=~/libs/TensorRT-$1/lib:$LD_LIBRARY_PATH

    # Display the TensorRT version
    echo "Using TensorRT version: $1"
}

# -----------------------------------------------------------------------------
# Function: sys_monitor
# Description: Brings up nvtop and htop in a tmux session for system
#   monitoring.
# Parameters: None
# Usage: sys_monitor
# -----------------------------------------------------------------------------
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

	# Attach to the session
	tmux attach -t sys_monitor
    fi
}

# -----------------------------------------------------------------------------
# Function: theme_mode
# Description: Switches between light and dark mode on the computer, updates
#   the terminal color scheme accordingly, and updates the VSCode theme.
# Parameters: None
# Usage: theme_mode
# -----------------------------------------------------------------------------
theme_mode() {
    # Define the light and dark theme names
    LIGHT_THEME="Yaru-light"
    DARK_THEME="Yaru-dark"

    # Define the UUIDs for the custom terminal profiles
    LIGHT_PROFILE_UUID="9c60621a-81a9-41a3-82a7-b0a0d6c57de7"
    DARK_PROFILE_UUID="b1dcc9dd-5262-4d8d-a863-c897e6d979b9"

    # Define VSCode themes
    VSCODE_LIGHT_THEME="Default Light Modern"
    VSCODE_DARK_THEME="Default Dark Modern"

    # Path to VSCode settings.json file
    VSCODE_SETTINGS_FILE="$HOME/.config/Code/User/settings.json"

    # Get the current GTK theme
    CURRENT_THEME=$(gsettings get org.gnome.desktop.interface gtk-theme)

    # Check the current theme and switch to the opposite theme
    if [[ $CURRENT_THEME == "'$LIGHT_THEME'" ]]; then
        gsettings set org.gnome.desktop.interface gtk-theme $DARK_THEME
        gsettings set org.gnome.Terminal.ProfilesList default $DARK_PROFILE_UUID
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

        # Update the VSCode theme
        jq --arg theme "$VSCODE_DARK_THEME" '.["workbench.colorTheme"] = $theme' $VSCODE_SETTINGS_FILE > temp.json && mv temp.json $VSCODE_SETTINGS_FILE

        echo "Switched to dark mode."
    else
        gsettings set org.gnome.desktop.interface gtk-theme $LIGHT_THEME
        gsettings set org.gnome.Terminal.ProfilesList default $LIGHT_PROFILE_UUID
        gsettings set org.gnome.desktop.interface color-scheme 'default'
        echo "Switched to light mode."

        # Update the VSCode theme
        jq --arg theme "$VSCODE_LIGHT_THEME" '.["workbench.colorTheme"] = $theme' $VSCODE_SETTINGS_FILE > temp.json && mv temp.json $VSCODE_SETTINGS_FILE
    fi
}


# -----------------------------------------------------------------------------
# Function: hypenate
# Description: Takes a string and replaces spaces with hyphens while removing
#   any special characters that the UNIX file system doesn't like. Then
#   prints the hyphenated string and set $HYPHENATED to the hyphenated string.
# Parameters:
#   $1 - The string to be hyphenated
# Usage: hypenate <string>
# -----------------------------------------------------------------------------
hyphenate() {
    # Replace spaces with hyphens
    HYPHENATED=$(echo $1 | sed 's/ /-/g')
    # Remove special characters
    HYPHENATED=$(echo $HYPHENATED | sed 's/[^a-zA-Z0-9-]//g')
    echo $HYPHENATED
}
