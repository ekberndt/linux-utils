# ------------------------------------------------------------------------
# This file defines the following phony targets for the make command
# which define recipes to be executed when the target is called by make.
# This make file can be thought of as a set of custom commands that can be
# used in this repository.
# Usage: make <target>
# ------------------------------------------------------------------------
.ONESHELL:
SHELL := /bin/bash
.DEFAULT_GOAL := help

# ------------------------------------------------------------------------
# Target: lint
# Description: Runs the given linter(s) on this repository. Defaults to
# running all linters if no linter is specified.
# - markdownlint
# - shellcheck
# Parameters:
#   - LINTERS: The linter(s) to run.
# Usage: make lint LINTERS=<linters...>
# 	Valid LINTERS: markdown, shell
# ------------------------------------------------------------------------
.PHONY: lint
lint:
	@LINTERS=$(LINTERS)

	if [ -z $$LINTERS ]; then
		echo "Running all linters..."
		LINTERS="markdown shell"
	fi

	# Directories to exclude from linting
	EXCLUDED_DIRS=(
		"src/external"
		"tools/scripts/external"
	)

	for linter in $$LINTERS; do
		echo "
		Running $$linter linter...
		"
		case $$linter in
			markdown)
				# Run markdownlint on all markdown files except EXCLUDED_DIRS
				MARKDOWNLINT_CMD="markdownlint-cli2 **/*.md"
				for dir in $${EXCLUDED_DIRS[@]}; do
					MARKDOWNLINT_CMD+=" \"#$$dir/**\""
				done
				eval "$$MARKDOWNLINT_CMD"
				;;
			shell)
				# Find all shell scripts expect EXCLUDED_DIRS
				FIND_CMD="find . -name '*.sh'"
				for dir in $${EXCLUDED_DIRS[@]}; do
					FIND_CMD+=" -not -path './$$dir/*'"
				done
				
				# Count the number of shell scripts to lint
				SHELL_SCRIPT_COUNT=$$(eval "$$FIND_CMD" | wc -l)
				# Check if there are any shell scripts to lint
				echo "Linting $$SHELL_SCRIPT_COUNT shell script(s) with shellcheck."
				if [ $$SHELL_SCRIPT_COUNT -gt 0 ] ; then
					# Pass the output of the find command as args to shellcheck
					eval "$$FIND_CMD" | xargs shellcheck;
				fi
				;;
			*)
				echo "Unknown linter: $$linter"
				exit 1
				;;
		esac
	done

	echo "Done linting."