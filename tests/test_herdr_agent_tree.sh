#!/bin/bash
set -uo pipefail

# The agent-tree Herdr mod is JavaScript the app runs; herdr_agent_tree.mjs
# renders it under node against stand-ins for the app's modules.

exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/herdr_agent_tree.mjs"
