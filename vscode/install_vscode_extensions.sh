#!/bin/bash

# -----------------------------------------------------------------------------
# Function: install_vscode_extensions
# Description: Reads the VSCode extensions.json file and installs the
#   extensions.
# Parameters:
#   $1 - extensions.json file from VSCode formatted as seen below:
#       {
#            "recommendations": [
#                "dbaeumer.vscode-eslint",
#                "ms-vscode.remote-explorer"
#            ]
#       }
# Usage: install_vscode_extensions <path/to/extensions.json>
# -----------------------------------------------------------------------------
install_vscode_extensions() {
    local extensions_file=$1

    if [ ! -f "$extensions_file" ]; then
        echo "File not found: $extensions_file"
        return 1
    fi

    local extension
    while IFS= read -r extension; do
        [[ -z "$extension" ]] && continue
        code --install-extension "$extension"
    done < <(jq -r '.recommendations[]?' "$extensions_file")
}
