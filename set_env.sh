#!/bin/bash
#-----------------------------------------------------------------------------
# SoC Labs Environment Setup Script
# Builds with Arm Quickstart IP only - no AAA licence required.
#
# Contributors
#
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright  2023-6, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Description:
# This script sets up the environment for the nanoSoC-M0 QuickStart project. It
# configures necessary paths, tools, and project-specific settings.
# The terminal echos are printed in different colours for visibility.
# The steps for this process are as follows:
# 1. Set the script directory as the working directory. If this is being
#    sourced from a different directory, it saves the current directory
#    and returns to it at the end.
#    It uses the script directory as the top-level of the project.
# 2. If the unset flag (--unset) is provided as an argument, it removes
#    configuration files (autoconfig, .socinit) and exits.
# 3. Source the set_env script from soctools_flow to configure the environment.
# 4. Sets up the system configuration by sourcing and running the
#    autoconfig_setup.sh script, which detects and configures development
#    tools like ARM toolchains and HDL simulators.
# 5. Runs init_repos.sh to initialize all sub-repositories.
# 6. Generates file lists for simulation.
#-----------------------------------------------------------------------------

echo -e "\033[1;32m==============================================="
echo "   nanoSoC-M0 QuickStart Environment Setup"
echo -e "===============================================\033[0m"

# Save current directory and change to script directory
pushd . > /dev/null

# Change the colour of the terminal output for visibility
echo -e "\n\033[1;34m-----------------------------------------------"
echo "Locating set_env script directory"
echo -e "-----------------------------------------------\033[0m"

# The script directory is the top-level of the project
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd $SCRIPT_DIR
echo "Running set_env: $SCRIPT_DIR/set_env.sh"

# Check to see if the unset flag has been provided
if [[ "$1" != "--unset" ]]; then
    # Source the project setup script
    echo -e "\n\033[1;34m-----------------------------------------------"
    echo "Sourcing SoC Labs Project Setup Script"
    echo -e "-----------------------------------------------\033[0m"
    source soctools_flow/bin/project_setup.sh $@

    # Source and run autoconfig setup
    echo -e "\n\033[1;34m-----------------------------------------------"
    echo "Setting up System Configuration"
    echo -e "-----------------------------------------------\033[0m"
    source soctools_flow/bin/autoconfig_setup.sh
    setup_all

    # If TOOL_CHAIN was set in the environment before set_env.sh was sourced,
    # override autoconfig so downstream make targets (e.g. bootrom) use it.
    # This is needed because autoconfig_setup.sh probes the PATH for compilers
    # in non-deterministic order and may select armclang instead of gcc.
    if [ -n "$TOOL_CHAIN" ]; then
        sed -i "s/^TOOL_CHAIN.*/TOOL_CHAIN = $TOOL_CHAIN/" autoconfig
    fi
fi

# Run the init_repos script to initialize subrepositories
source soctools_flow/bin/init_repos.sh $@

# Generate file lists for simulation
if [[ "$1" != "--unset" ]]; then
    echo -e "\n\033[1;34m-----------------------------------------------"
    echo "Generating File Lists for Simulation"
    echo -e "-----------------------------------------------\033[0m"
    make -C nanosoc_m0_soc/nanosoc_arch_tech flist_vfiles_nanosoc

    # Run the filelist checker to ensure all files exist
    echo -e "\n\033[1;34m-----------------------------------------------"
    echo "Check filelists to ensure all files exist"
    echo -e "-----------------------------------------------\033[0m"
    python $SOCLABS_SOCTOOLS_FLOW_DIR/bin/filelist_checker.py -i $SOCLABS_PROJECT_DIR/simulate/sim/hello/tbench.vc
else
    # Change the terminal output colour for visibility to Red
    echo -e "\n\033[1;31m-----------------------------------------------"
    echo "Unset flag (--unset) provided. Removing environment configuration files."
    echo -e "-----------------------------------------------\033[0m"

    # Remove Configuration files
    rm -f autoconfig
    rm -f .socinit

    echo "Environment unset completed."
    echo "The following files have been removed if they existed:"
    echo " - autoconfig"
    echo " - .socinit"
    echo -e "\033[0m"
fi

# Return to the directory the script was sourced from
popd > /dev/null
