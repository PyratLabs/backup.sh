#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# You need to enable this to use it.
__MYSQLDUMP_BACKUP_ENABLE=false

# MySQL Hostname
__MYSQLDUMP_HOST=localhost

# MySQL Username
__MYSQLDUMP_USER="backup"

# MySQL Password
__MYSQLDUMP_PASS="PASSW0RD"

# Dump all databases (Overrides below)
__MYSQLDUMP_DUMP_ALL=true

# MySQL Dump specific databases
__MYSQLDUMP_DATABASES=(
    "testdb"
    "testdb2"
)

mysqldump_setup() {
    __MYSQLDUMP=$(which mysqldump || true)

    if [[ "${__MYSQLDUMP}" == "" ]] ; then
        fatal "mysqldump not found. Please install before using this plugin."
    fi

    info "Using MySQL Dump to backup databases."
}

mysqldump_compress() {
    if [[ ${__BACKUP_COMPRESSION} == false ]] ; then
        return 0
    fi

    case "${__BACKUP_COMPRESSION_METHOD}" in
        gz)
            __COMPRESS=$(which gzip || true)
            ;;
        bz2)
            __COMPRESS=$(which bzip2 || true)
            ;;
        xz)
            __COMPRESS=$(which xz || true)
            ;;
        lzma)
            __COMPRESS=$(which lzma || true)
            ;;
        *)
            error "Unrecognised compression method: " \
                "${__BACKUP_COMPRESSION_METHOD}. Using gz."
            __COMPRESS=$(which gzip || true)
            ;;
    esac

    if [[ "${__COMPRESS}" == "" ]] ; then
        fatal "Compression method ${__BACKUP_COMPRESSION_METHOD} not found."
    else
        info "Compressing ${1} using: ${__COMPRESS}."
        ${__COMPRESS} "${1}"
    fi
}

mysqldump_export() {
    local __TARGET
    if [[ ${__MYSQLDUMP_DUMP_ALL} == true ]] ; then
        __TARGET="${1}/${__MYSQLDUMP_HOST}.sql"
        ${__MYSQLDUMP} \
            --host="${__MYSQLDUMP_HOST}" \
            --user="${__MYSQLDUMP_USER}" \
            --password="${__MYSQLDUMP_PASS}" \
            --all-databases > "${__TARGET}" || \
        error "mysqldump --all-databases failed."
        test -f "${__TARGET}" && mysqldump_compress "${__TARGET}"
    else
        for database in "${__MYSQLDUMP_DATABASES[@]}" ; do
            __TARGET="${1}/${database}.sql"
            ${__MYSQLDUMP} \
                --host="${__MYSQLDUMP_HOST}" \
                --user="${__MYSQLDUMP_USER}" \
                --password="${__MYSQLDUMP_PASS}" \
                "${database}" > "${__TARGET}" || \
            error "mysqldump ${database} failed."
            test -f "${__TARGET}" && mysqldump_compress "${__TARGET}"
        done
    fi
}

mysqldump_exec() {
    if [[ ${__MYSQLDUMP_BACKUP_ENABLE} != true ]] ; then
        info "mysqldump plugin disabled."
        return 0
    fi

    mysqldump_setup
    mysqldump_export "${1}"
    info "Completed MySQL Dump backup."
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]] ; then
    echo "Script should be sourced, not executed!"
    exit 1
fi
