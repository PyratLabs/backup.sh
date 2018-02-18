#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# You need to enable this to use it.
__S3_BACKUP_ENABLE=false

# s3 configuration.
__S3_BUCKET="bucket-name"

# You'll need the following to be set up.
# [AWS_ACCESS_KEY]
# [AWS_ACCESS_SECRET]

s3_setup() {
    __AWS=$(which aws || true)

    if [[ "${__AWS}" == "" ]] ; then
        fatal "awscli not found. Please install before using this plugin."
    fi

    info "Backing up to s3://${__S3_BUCKET}."
}

s3_put() {
    test -d "${1}" || error "${1} is not a directory."
    ${__AWS} s3 sync "${1}" "s3://${__S3_BUCKET}/" || \
        error "s3 backup failed."
}

s3_exec() {
    if [[ ${__S3_BACKUP_ENABLE} != true ]] ; then
        info "s3 plugin disabled."
        return 0
    fi

    s3_setup
    s3_put "${1}"
    info "Completed aws backup."
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]] ; then
    echo "Script should be sourced, not executed!"
    exit 1
fi
