# backup.sh

### Version 1.1.4

Pure bash implementation backup script for GNU/Linux, BSD and UNIX.
backup.sh can put encrypted backups on local or remote servers.

## Specification

Extendible, general purpose backup script written in bash. Compresses,
encrypts and copies to remote.

All scripts and plugins are written in bash and are checked against
[ShellCheck](https://www.shellcheck.net/), max columns of 80 characters to
ensure easy editing over SSH session.

Currently creates backup files with one week retention with the following
pattern:

`/path/to/backup/$(hostname)/$(date "+%A")`

Further development will look at different retention periods including
weekly and monthly backups.

## Usage

```
backup.sh - v1.1.4
------------------
(c) PyratLabs 2017

Usage:
  backup.sh [options]
Description:
  Pure bash implementation backup script for GNU/Linux, BSD and UNIX.
  backup.sh can put encrypted backups on local or remote servers.
Source:
  https://github.com/PyratLabs/backup.sh
Examples:
  Backup to local filesystem without using encryption
     backup.sh --no-encryption --local-only
  Backup without compression
     backup.sh --no-compression
  Backup using lzma compression
     backup.sh --lzma
Options:
  --help:                Display this help message
  --gzip:                Use gzip compression (Default)
  --bzip:                Use bzip2 compression
  --xz:                  Use xz compresion
  --lzma:                Use lzma compresion
  --local-only:          Only back up locally
  --no-ascii:            Do not use --armor option
  --no-encryption:       Do not use PGP/GPG2 encryption
  --no-compression:      Do not compress, just archive
  --no-application:      Do not use external applications to backup
  --no-color:            Do not use colored output
```

## Plugins

backup.sh will accept shell scripts in the `plugins/` directory to extend
functionality.

### Application

Shell script wrappers to execute a command.

  * `plugins/application/mysqldump.sh` - Performs a MySQL dump of a database
    and puts it in the backup directory for encryption.

### Remotes

Shell script wrappers to synchronize backups to a remote server.

  * `plugins/remote/s3.sh` - Remotely syncs the local backup directory to
    AWS S3.
  * `plugins/remote/rsync.sh` - Remotely syncs the local backup directory to
    a chosen rsync target.
