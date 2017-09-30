#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

__BACKUP_DIRS=(
    /etc
#    /home/*
#    /var/log
)

__BACKUP_OUT="./backups"

__BACKUP_COMPRESSION=true
__BACKUP_COMPRESSION_METHOD="gz"
__BACKUP_ENCRYPTION=true
__BACKUP_ENCRYPTION_KEYDIR="./pubkey"

#/
#/ backup.sh
#/ ---------
#/ (c) PyratLabs 2017
#/
#/ Usage:
#/   backup.sh [options]
#/ Description:
#/   Pure bash implementation backup script for GNU/Linux, BSD and UNIX.
#/   backup.sh can put encrypted backups on local or remote servers.
#/ Source:
#/   https://github.com/PyratLabs/backup.sh
#/ Examples:
#/   ./backup.sh
#/ Options:
#/   --help:                Display this help message
#/   --local-only:          Only back up locally
#/   --gzip:                Use gzip compression (Default)
#/   --bzip:                Use bzip2 compression
#/   --xz:                  Use xz compresion
#/   --lzma:                Use lzma compresion
#/   --no-encrypt:          Do not use PGP/GPG2 encryption
#/   --no-compression:      Do not compress, just archive
#/
usage() { grep '^#/' "${0}" | cut -c4- ; exit 0 ; }
expr "$*" : ".*--help" > /dev/null && usage
__OPTS=$*

readonly LOG_FILE="/tmp/$(basename "${0}").log"
info()      { echo "[INFO]    $*"    | tee -a "${LOG_FILE}" >&2 ; }
warning()   { echo "[WARNING] $*"    | tee -a "${LOG_FILE}" >&2 ; }
error()     { echo "[ERROR]   $*"    | tee -a "${LOG_FILE}" >&2 ; }
fatal()     { echo "[FATAL]   $*"    | tee -a "${LOG_FILE}" >&2 ; exit 1 ; }
timestamp() { echo "[TIME]    $(date)" | tee -a "${LOG_FILE}" >&2 ; }

parseops() {
    for opt in ${__OPTS} ; do
        case "${opt}" in
            --no-compression)
                __BACKUP_COMPRESSION=false
                ;;
            --gzip)
                __BACKUP_COMPRESSION_METHOD="gz"
                ;;
            --bzip2)
                __BACKUP_COMPRESSION_METHOD="bz2"
                ;;
            --xz)
                __BACKUP_COMPRESSION_METHOD="xz"
                ;;
            --lzma)
                __BACKUP_COMPRESSION_METHOD="lzma"
                ;;
            --no-encrypt)
                __BACKUP_ENCRYPTION=false
                ;;
        esac
    done
}

setup() {
    # Create the temporary directory setup.
    timestamp
    __TMPDIR=$(mktemp -d /tmp/backup.XXXXXXXX)
    info "${__TMPDIR} created."

    # Find the required dependencies for backup.
    __ARCHIVE=$(which tar || true)
    __ENCRYPT=$(which gpg2 || which pgp || true)
    __RSYNC=$(which rsync || true)

    if [[ ${#__ARCHIVE} -eq 0 ]] ; then
        fatal "No archiving method found."
    else
        info "Archiving using: ${__ARCHIVE}."
    fi

    if [[ ${#__RSYNC} -eq 0 ]] ; then
        fatal "Rsync not found."
    else
        info "Rsync using: ${__ARCHIVE}."
    fi

    if [[ ${#__ENCRYPT} -eq 0 ]] ; then
        warning "No encryption method found. Proceeding without encryption."
        __BACKUP_ENCRYPTION=false
    else
        info "Encrypting using: ${__ENCRYPT}."
        test -d ${__BACKUP_ENCRYPTION_KEYDIR} || \
            fatal "Cannot read from ${__BACKUP_ENCRYPTION_KEYDIR}"
    fi

    if [[ ${__BACKUP_ENCRYPTION} == true ]] ; then
        info "Setting up encryption keychain."
        mkdir "${__TMPDIR}/keychain"
        chmod 0700 "${__TMPDIR}/keychain"

        for key in ${__BACKUP_ENCRYPTION_KEYDIR}/*.pub ; do
            info "Importing ${key}"
            ${__ENCRYPT} \
                --homedir "${__TMPDIR}/keychain" \
                --import ${key}
        done
    fi

    __DAYNAME=$(date "+%A")
    __HOSTNAME=$(hostname)
    __OUTDIR="${__BACKUP_OUT}/${__HOSTNAME}/${__DAYNAME}"
}

archive() {
    for target in ${__BACKUP_DIRS[@]} ; do
        if [[ -d ${target} ]] ; then
            info "Backing up ${target}"
            local tarname=$(echo "${target:1}" | sed -e 's/\//-/')
            if [[ ${__BACKUP_COMPRESSION} == false ]] ; then
                ${__ARCHIVE} \
                    -cvf ${__TMPDIR}/${tarname}.tar \
                    ${target} || fatal "Could not backup ${target}"
            else
                case "${__BACKUP_COMPRESSION_METHOD}" in
                    gz)
                        ${__ARCHIVE} \
                            -cvzf ${__TMPDIR}/${tarname}.tar.gz \
                            ${target} || fatal "Could not backup ${target}"
                        ;;
                    bz2)
                        ${__ARCHIVE} \
                            -cvjf ${__TMPDIR}/${tarname}.tar.bz2 \
                            ${target} || fatal "Could not backup ${target}"
                        ;;
                    xz)
                        ${__ARCHIVE} \
                            -cvJf ${__TMPDIR}/${tarname}.tar.xz \
                            ${target} || fatal "Could not backup ${target}"
                        ;;
                    lzma)
                        ${__ARCHIVE} \
                            --lzma -cvf ${__TMPDIR}/${tarname}.tar.lzma \
                            ${target} || fatal "Could not backup ${target}"
                        ;;
                    *)
                        error "Unrecognised compression method: " \
                            "${__BACKUP_COMPRESSION_METHOD}. Using gz."
                        ${__ARCHIVE} \
                            -cvzf ${__TMPDIR}/${tarname}.tar.gz \
                            ${target} || fatal "Could not backup ${target}"
                        ;;
                esac
            fi
        fi
    done
}

encrypt() {
    if [[ ${__BACKUP_ENCRYPTION} != true ]] ; then
        return 0
    fi

    __PUBLIC_KEYS=$(${__ENCRYPT} \
        --homedir "${__TMPDIR}/keychain" \
        --list-public-keys \
        --with-colons | \
        awk -F':' '/^uid/ { print $10 }' | \
        awk '{ print $NF }' | \
        sed -e 's/[<>]//g')

    __RECIPIENTS=()

    for key in ${__PUBLIC_KEYS} ; do
        __RECIPIENTS+=("-r ${key}")
    done

    for file in ${__TMPDIR}/* ; do
        if [[ -f ${file} ]] ; then
            "${__ENCRYPT}" \
                --homedir "${__TMPDIR}/keychain" \
                --trust-model always \
                -ea \
                "${__RECIPIENTS[@]}" \
                "${file}" || error "Could not encrypt ${file}"
            rm "${file}"
        fi
    done
}

local_backup() {
    info "Moving backups from ${__TMPDIR} to ${__BACKUP_OUT}"
    test -d "${__BACKUP_OUT}" || \
        mkdir "${__BACKUP_OUT}" || \
        fatal "Cannot write to ${__BACKUP_OUT}"

    mkdir -p ${__OUTDIR} || \
        fatal "Cannot write to ${__BACKUP_OUT}"

    ${__RSYNC} --exclude "keychain" -rl "${__TMPDIR}/" "${__OUTDIR}/"
}

cleanup() {
    # Move log is outdir exists
    info "Moving log to ${__BACKUP_OUT}"
    test -d ${__OUTDIR} && mv "${LOG_FILE}" "${__OUTDIR}"
    # Cleanup temporary directory.
    rm -r ${__TMPDIR} && \
        info "${__TMPDIR} removed." || \
        error "Could not remove ${__TMPDIR}"

    timestamp
    return 0
}

if [[ "${BASH_SOURCE[0]}" = "${0}" ]] ; then
    trap cleanup EXIT
    parseops
    setup
    archive
    encrypt
    local_backup
fi
