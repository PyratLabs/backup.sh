#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# You need to enable this to use it.
__SENDMAIL_ENABLE=false

# Email Recipient(s)
__SENDMAIL_RECIPIENTS=(
  "mail@example.com"
  "other@email.com"
)

# Email subject ID
__SENDMAIL_SUBJECT=$(hostname)

sendmail_setup() {
    __MAIL=$(command -v mail || true)

    if [[ "${__MAIL}" == "" ]] ; then
        fatal "mail command not found. Please install before using this plugin."
    fi
}

sendmail_exec() {
    if [[ ${__SENDMAIL_ENABLE} != true ]] ; then
        info "sendmail plugin disabled."
        return 0
    fi

    if [[ ${__ERR} -gt 0 ]] ; then
        __SUBJECT="[${__SENDMAIL_SUBJECT}] Backup experienced errors"
    else
        __SUBJECT="[${__SENDMAIL_SUBJECT}] Backup completed successfully"
    fi

    sendmail_setup
    for mailout in "${__SENDMAIL_RECIPIENTS[@]}" ; do
        info "Sending mail notification to: ${mailout}"
        ${__MAIL} -s "${__SUBJECT}" "${mailout}" < "${LOG_FILE}" || \
            error "Failed to send mail notification."
    done
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]] ; then
    echo "Script should be sourced, not executed!"
    exit 1
fi
