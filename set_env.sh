#!/bin/bash
#-----------------------------------------------------------------------------
# nanoSoC-M0 QuickStart — environment setup
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Usage:  source set_env.sh  [--unset]
#
# Deliberately simpler than the SoC Labs project template, for two reasons that
# are not stylistic:
#
# 1. NO subrepo_checkout.py. The template's project_setup.sh runs it on first
#    use, and it does `git checkout --recurse-submodules <branch>` followed by
#    `git pull` in every sub-repo (subrepo_checkout.py:44-48). This project uses
#    ordinary git submodules, so that would move them off whatever you have
#    checked out -- including a feature branch you are mid-way through -- and
#    silently revert your working tree to the recorded pins. We create .socinit
#    ourselves to skip it, and use `git submodule update --init --recursive`,
#    which does the same job without moving branches you did not ask it to move.
#
# 2. NO autoconfig_setup.sh. That script probes $PATH for a toolchain and a
#    simulator and writes the two lines that end up in ./autoconfig. The probe
#    is order-dependent -- the template's own set_env.sh carries a sed to undo
#    it when it picks armclang over gcc -- and it lives only on the unmerged
#    soctools_flow branch `dm-set_env_updates`, not on main. So autoconfig is a
#    committed file here. Override either value from the environment.
#-----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
pushd . > /dev/null
cd "$SCRIPT_DIR"

if [[ "$1" == "--unset" ]]; then
    echo -e "\033[1;31m--- Removing environment configuration ---\033[0m"
    rm -f .socinit
    echo "Removed .socinit. autoconfig is committed and is left alone."
    popd > /dev/null
    return 0 2>/dev/null || exit 0
fi

echo -e "\033[1;32m=============================================="
echo "   nanoSoC-M0 QuickStart Environment Setup"
echo -e "==============================================\033[0m"

# --- Submodules, via plain git, WITHOUT clobbering work in progress -----------
#
# `git submodule update` checks out the RECORDED PIN. If a submodule is sitting
# on a branch you are working on, and the superproject has not recorded that
# branch's commit yet, a plain update silently reverts your checkout to the pin.
# The commits survive on the branch; the working tree does not, and nothing says
# so. This bit the author of this script, which is why it reads like this.
#
# So: initialise submodules that are ABSENT, and leave alone any that are
# already checked out on a branch or carrying local modifications.
echo -e "\n\033[1;34m--- Submodules ---\033[0m"
git submodule status --recursive 2>/dev/null | while read -r line; do
    state="${line:0:1}"; path=$(echo "$line" | awk '{print $2}')
    case "$state" in
        -) echo "  init    $path"; git submodule update --init --recursive -- "$path" >/dev/null 2>&1 ;;
        +) branch=$(git -C "$path" branch --show-current 2>/dev/null)
           if [ -n "$branch" ]; then
               echo -e "  \033[1;33mSKIP    $path -- on branch '$branch', not at the recorded pin\033[0m"
               echo    "          Leaving it alone. Commit and push it, then bump the pin."
           else
               echo -e "  \033[1;33mSKIP    $path -- detached at a commit that is not the pin\033[0m"
           fi ;;
        U) echo -e "  \033[1;31mCONFLICT $path -- resolve by hand\033[0m" ;;
        *) echo "  ok      $path" ;;
    esac
done

# --- Skip the template's sub-repo checkout ------------------------------------
# project_setup.sh only runs subrepo_checkout.py when .socinit is absent.
if [ ! -f .socinit ]; then
    echo "Skipping subrepo_checkout.py -- this project uses git submodules." > .socinit
fi

# --- Project environment ------------------------------------------------------
echo -e "\n\033[1;34m--- Project environment ---\033[0m"
source soctools_flow/bin/project_setup.sh

# --- Arm Quickstart IP --------------------------------------------------------
echo -e "\n\033[1;34m--- Arm Quickstart IP ---\033[0m"
if [ -z "$ARM_QS_IP_DIR" ] && [ -z "$ARM_IP_LIBRARY_PATH" ]; then
    echo -e "\033[1;31mNeither ARM_QS_IP_DIR nor ARM_IP_LIBRARY_PATH is set.\033[0m"
    echo "Set ARM_QS_IP_DIR to your unpacked Cortex-M0 Quickstart download."
    echo "It must contain Cortex-M0-logical/ and Corstone-101-logical/."
else
    QS_ROOT="${ARM_QS_IP_DIR:-$ARM_IP_LIBRARY_PATH/latest/Cortex-M0-QS}"
    for d in Cortex-M0-logical Corstone-101-logical; do
        if [ -d "$QS_ROOT/$d" ]; then echo "  found  $QS_ROOT/$d"
        else echo -e "  \033[1;31mMISSING $QS_ROOT/$d\033[0m"; fi
    done
fi

# --- Filelists ----------------------------------------------------------------
echo -e "\n\033[1;34m--- Generating filelists ---\033[0m"
make -C nanosoc_m0_soc/nanosoc_arch_tech flist_vfiles_nanosoc

popd > /dev/null
