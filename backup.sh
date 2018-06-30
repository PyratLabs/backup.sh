#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

#/
#/ backup.sh - v1.1.6
#/ ------------------
#/ (c) PyratLabs 2017
#/
#/ Usage:
#/   ./backup.sh [options]
#/ Description:
#/   Pure bash implementation backup script for GNU/Linux, BSD and UNIX.
#/   ./backup.sh can put encrypted backups on local or remote servers.
#/ Source:
#/   https://github.com/PyratLabs/backup.sh
#/ Examples:
#/   Backup to local filesystem without using encryption
#/      ./backup.sh --no-encryption --local-only
#/   Backup without compression
#/      ./backup.sh --no-compression
#/   Backup using lzma compression
#/      ./backup.sh --lzma
#/ Options:
#/   --help:                Display this help message
#/   --gzip:                Use gzip compression (Default)
#/   --bzip:                Use bzip2 compression
#/   --xz:                  Use xz compresion
#/   --lzma:                Use lzma compresion
#/   --local-only:          Only back up locally
#/   --no-ascii:            Do not use --armor option
#/   --no-encryption:       Do not use PGP/GPG2 encryption
#/   --no-compression:      Do not compress, just archive
#/   --no-application:      Do not use external applications to backup
#/   --no-color:            Do not use colored output
#/

#
# START CONFIGURATION
#

# Array of directories to backup
# Wildcards can be used to chunk backup directories
__BACKUP_DIRS=(
    /etc
    /home/*
    /var/www/*
)

# Directory to backup to
__BACKUP_OUT="/tmp/backups"

# Backup date format (may be used for overwriting backups, +eg. %A = Monday)
__BACKUP_DATE_FORMAT="+%A"

# Backup Retention
# How many backups should we keep? (set to 'false' to retain all backups)
__BACKUP_RETENTION=7

# Compress backup archives, which method?
__BACKUP_COMPRESSION=true
__BACKUP_COMPRESSION_METHOD="gz"

# Encrypt the backups? Which public key directory?
__BACKUP_ENCRYPTION=true
__BACKUP_ENCRYPTION_ASCII=true
__BACKUP_ENCRYPTION_KEYDIR="pubkey"

# Backup applications? Loads functions from plugins/applications
__BACKUP_APPLICATION=true

# Backup to remote server? Loads functions from plugins/remote
__BACKUP_REMOTE=true

#
# END CONFIGURATION
#



usage() {
    local __F
    __F=$(basename "${0}")
    grep '^#/' "${0}" | sed -e "s#\./backup.sh#${__F}#g" | cut -c4-
    exit 0
}

expr "$*" : ".*--help" > /dev/null && usage
expr "$*" : ".*-h" > /dev/null && usage
__ERR=0
__OPTS=$*
__CR="$(tput setaf 1)$(tput bold)"
__CG="$(tput setaf 2)$(tput bold)"
__CY="$(tput setaf 3)$(tput bold)"
__CM="$(tput setaf 5)$(tput bold)"
__CC="$(tput setaf 4)$(tput bold)"
__CK="$(tput sgr0)"
__PWD=${BASH_SOURCE%/*}



parseops() {
    for opt in ${__OPTS} ; do
        case "${opt}" in
            --local-only)
                __BACKUP_REMOTE=false
                ;;
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
            --no-ascii)
                __BACKUP_ENCRYPTION_ASCII=false
                ;;
            --no-encryption)
                __BACKUP_ENCRYPTION=false
                ;;
            --no-application)
                __BACKUP_APPLICATION=false
                ;;
            --no-color|--no-colour)
                __CR=""
                __CG=""
                __CY=""
                __CM=""
                __CC=""
                __CK=""
                ;;
        esac
    done
}

readonly LOG_FILE="/tmp/$(basename "${0}").log"
ok()        { echo "${__CG}[OK]${__CK}      $*"      | tee -a "${LOG_FILE}" >&2 ; }
info()      { echo "${__CC}[INFO]${__CK}    $*"      | tee -a "${LOG_FILE}" >&2 ; }
warning()   { echo "${__CY}[WARNING]${__CK} $*"      | tee -a "${LOG_FILE}" >&2 ; }
error()     { echo "${__CR}[ERROR]${__CK}   $*"      | tee -a "${LOG_FILE}" >&2 ; __ERR=1 ; }
fatal()     { echo "${__CM}[FATAL]${__CK}   $*"      | tee -a "${LOG_FILE}" >&2 ; __ERR=1 ; exit 1 ; }
timestamp() { echo "${__CK}[TIME]${__CK}    $(date)" | tee -a "${LOG_FILE}" >&2 ; }

setup() {
    # Create the temporary directory setup.
    timestamp
    __TMPDIR=$(mktemp -d /tmp/backup.XXXXXXXX)
    info "${__TMPDIR} created."

    # Find the required dependencies for backup.
    __ARCHIVE=$(which tar || true)
    __ENCRYPT=$(which gpg2 || which pgp || true)
    __RSYNC=$(which rsync || true)

    if [[ "${__ARCHIVE}" == "" ]] ; then
        fatal "No archiving method found."
    else
        info "Archiving using: ${__ARCHIVE}."
    fi

    if [[ "${__RSYNC}" == "" ]] ; then
        fatal "Rsync not found."
    else
        info "Rsync using: ${__RSYNC}."
    fi

    local __PATHMATCH
    local __KEYDIR

    if [[ "${__BACKUP_ENCRYPTION_KEYDIR:0:1}" == "/" ]] ; then
        __PATHMATCH="${__BACKUP_ENCRYPTION_KEYDIR}"
        __KEYDIR="${__BACKUP_ENCRYPTION_KEYDIR}"
    else
        __PATHMATCH="${__PWD}/${__BACKUP_ENCRYPTION_KEYDIR}"
        __KEYDIR="${__PWD}/${__BACKUP_ENCRYPTION_KEYDIR}"
    fi

    if [[ "${__ENCRYPT}" == "" ]] ; then
        warning "No encryption method found. Proceeding without encryption."
        __BACKUP_ENCRYPTION=false
    else
        info "Encrypting using: ${__ENCRYPT}."
        test -d "${__KEYDIR}" || fatal "Cannot read from ${__KEYDIR}"
    fi

    if [[ ${__BACKUP_ENCRYPTION} == true ]] ; then
        info "Checking for keys in ${__PATHMATCH}"
        __PUBKEYS_COUNT=$(find "${__PATHMATCH}" -type f -name "*.pub" | wc -l)

        if [[ ${__PUBKEYS_COUNT} -lt 1 ]] ; then
            warning "No keys found in ${__PATHMATCH}. Disabling encryption."
            __BACKUP_ENCRYPTION=false
        else
            info "Setting up encryption keychain."
            mkdir "${__TMPDIR}/.keychain"
            chmod 0700 "${__TMPDIR}/.keychain"

            for key in "${__PATHMATCH}/"*.pub ; do
                info "Importing ${key}"
                if [[ -f "${key}" ]] ; then
                    ${__ENCRYPT} \
                        --homedir "${__TMPDIR}/.keychain" \
                        --import "${key}"
                else
                    warning "${key} is not a file."
                fi
            done
        fi
    fi

    __DATENAME=$(date "${__BACKUP_DATE_FORMAT}")
    __HOSTNAME=$(hostname)
    __HOST_OUTDIR="${__BACKUP_OUT}/${__HOSTNAME}"
    __OUTDIR="${__HOST_OUTDIR}/${__DATENAME}"
}

archive() {
    for target in "${__BACKUP_DIRS[@]}" ; do
        if [[ -r ${target} ]] ; then
            info "Backing up ${target}"
            local __TARNAME
            __TARNAME=$(echo "${target:1}" | sed -e 's/\//-/g')
            if [[ ${__BACKUP_COMPRESSION} == false ]] ; then
                ${__ARCHIVE} \
                    -cvf "${__TMPDIR}/${__TARNAME}.tar" \
                    "${target}" || fatal "Could not backup ${target}"
            else
                case "${__BACKUP_COMPRESSION_METHOD}" in
                    gz)
                        ${__ARCHIVE} \
                            -cvzf "${__TMPDIR}/${__TARNAME}.tar.gz" \
                            "${target}" || fatal "Could not backup ${target}"
                        ;;
                    bz2)
                        ${__ARCHIVE} \
                            -cvjf "${__TMPDIR}/${__TARNAME}.tar.bz2" \
                            "${target}" || fatal "Could not backup ${target}"
                        ;;
                    xz)
                        ${__ARCHIVE} \
                            -cvJf "${__TMPDIR}/${__TARNAME}.tar.xz" \
                            "${target}" || fatal "Could not backup ${target}"
                        ;;
                    lzma)
                        ${__ARCHIVE} \
                            --lzma -cvf "${__TMPDIR}/${__TARNAME}.tar.lzma" \
                            "${target}" || fatal "Could not backup ${target}"
                        ;;
                    *)
                        error "Unrecognised compression method: " \
                            "${__BACKUP_COMPRESSION_METHOD}. Using gz."
                        ${__ARCHIVE} \
                            -cvzf "${__TMPDIR}/${__TARNAME}.tar.gz" \
                            "${target}" || fatal "Could not backup ${target}"
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

    local __ASCII

    if [[ ${__BACKUP_ENCRYPTION_ASCII} != true ]] ; then
        __ASCII="-e"
    else
        __ASCII="-ea"
    fi

    local __PUBLIC_KEYS
    __PUBLIC_KEYS=$(${__ENCRYPT} \
        --homedir "${__TMPDIR}/.keychain" \
        --list-public-keys \
        --with-colons | \
        awk -F':' '/^uid/ { print $10 }' | \
        awk '{ print $NF }' | \
        sed -e 's/[<>]//g')

    local __RECIPIENTS
    __RECIPIENTS=()

    for key in ${__PUBLIC_KEYS} ; do
        __RECIPIENTS+=("-r ${key}")
    done

    for file in ${__TMPDIR}/* ; do
        if [[ -f ${file} ]] ; then
            "${__ENCRYPT}" \
                --homedir "${__TMPDIR}/.keychain" \
                --trust-model always \
                "${__ASCII}" \
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

    mkdir -p "${__OUTDIR}" || \
        fatal "Cannot write to ${__BACKUP_OUT}"

    ${__RSYNC} --exclude ".keychain" -rl "${__TMPDIR}/" "${__OUTDIR}/"
}

application_backup() {
    if [[ ${__BACKUP_APPLICATION} != true ]] ; then
        return 0
    fi

    test -d "${__PWD}/plugins/application" || \
        fatal "Cannot find application plugin dir."

    local __I
    local __FREMOTE
    local __RBACK

    __I=0

    info "Application backups enabled."
    for application in ${__PWD}/plugins/application/* ; do
        if [[ -f ${application} ]] ; then
            __FAPP=$(basename "${application}")
            __ABACK=${__FAPP%%.*}
            info "Application backup plugin found: ${__ABACK}"
            # shellcheck source=/dev/null
            source "${application}"
            "${__ABACK}_exec" "${__TMPDIR}"
            __I+=1
        fi
    done

    if [[ ${__I} -lt 1 ]] ; then
        warning "No application backup plugin found."
    fi
}

remote_backup() {
    if [[ ${__BACKUP_REMOTE} != true ]] ; then
        return 0
    fi

    test -d "${__PWD}/plugins/remote" || fatal "Cannot find remote plugin dir."

    local __I
    local __FREMOTE
    local __RBACK

    __I=0

    info "Remote backups enabled."
    for remote in ${__PWD}/plugins/remote/* ; do
        if [[ -f ${remote} ]] ; then
            __FREMOTE=$(basename "${remote}")
            __RBACK=${__FREMOTE%%.*}
            info "Remote backup plugin found: ${__RBACK}"
            # shellcheck source=/dev/null
            source "${remote}"
            "${__RBACK}_exec" "${__BACKUP_OUT}"
            __I+=1
        fi
    done

    if [[ ${__I} -lt 1 ]] ; then
        warning "No remote backup plugin found."
    fi
}

clean_old_backups() {
    if [[ "${__BACKUP_RETENTION}" == false ]] ; then
        info "No explicit backup retention policy set."
        return 0
    fi

    info "Backup retention policy: ${__BACKUP_RETENTION} backups."
    info "Building Manifest"
    find "${__HOST_OUTDIR}" \
        -maxdepth 1 \
        -type d \
        -not -path "${__HOST_OUTDIR}" \
        -exec stat -c "%Y %n" {} \; > "${__HOST_OUTDIR}/backup.MANIFEST"
    if [[ "${?}" -gt 0 ]] ; then
        error "Could not build manifest file"
    else
        __I=0
        for backup in $(sort -nr "${__HOST_OUTDIR}/backup.MANIFEST") ; do
            __BACKDIR=$(echo "${backup}" | awk '{ print $NF }')
            if [[ "${__I}" -gt "${__BACKUP_RETENTION}" ]] ; then
                info "Old backup: ${__BACKDIR} removed."
                test -d "${__BACKDIR}" && rm -r "${__BACKDIR}"
            fi
            __I+=1
        done
    fi
    test -f "${__HOST_OUTDIR}/backup.MANIFEST" && \
        rm "${__HOST_OUTDIR}/backup.MANIFEST"
}

cleanup() {
    if [[ "${__ERR}" -gt 0 ]] ; then
        warning "Backup completed with errors."
    else
        ok "Backup completed successfully."
    fi
    # Move log is outdir exists
    info "Moving log to ${__BACKUP_OUT}"
    test -d "${__OUTDIR}" && mv "${LOG_FILE}" "${__OUTDIR}"
    # Cleanup temporary directory.
    rm -r "${__TMPDIR}" || \
        error "Could not remove ${__TMPDIR}"

    test -d "${__TMPDIR}" || info "${__TMPDIR} removed."

    timestamp
    return 0
}

if [[ "${BASH_SOURCE[0]}" = "${0}" ]] ; then
    trap cleanup EXIT
    parseops
    setup
    archive
    application_backup
    encrypt
    local_backup
    remote_backup
    clean_old_backups
fi
