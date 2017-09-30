#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# You need to enable this to use it.
__RSYNCR_ENABLE=false

# Rsync options
__RSYNCR_OPTS="-arvvlPHS"
__RSYNCR_TARGET="/tmp/rsync_backups"

rsync_setup() {
    __RSYNCR=$(which rsync || true)

    if [[ ${#__RSYNCR} -eq 0 ]] ; then
        fatal "rsync not found. Please install before using this plugin."
    fi

    info "Rsync to ${__RSYNCR_TARGET}."
}

rsync_sync() {
    test -d "${1}" || error "${1} is not a directory."
    ${__RSYNCR} "${__RSYNCR_OPTS}" "${1}/" "${__RSYNCR_TARGET}/" || \
        error "Rsync failed."
}

rsync_exec() {
    if [[ ${__RSYNCR_ENABLE} != true ]] ; then
        info "rsync plugin disabled."
        return 0
    fi

    rsync_setup
    rsync_sync "${1}"
    info "Completed rsync."
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]] ; then
    echo "Script should be sourced, not executed!"
    exit 1
fi
