#!/bin/sh
#
# Download, verify and install the Geant4 datasets, and write the environment
# file that points at them.
#
# This is what the macOS postinstall and the Debian postinst both run, so that
# the two behave like the Windows installer: the datasets are fetched and
# configured while the package is being installed, not left to the user.  It is
# also usable on its own; after an upgrade, or to add a dataset that was not
# selected the first time:
#
#   sudo ./fetch-datasets.sh --prefix /opt/geant4/11.4.3 --all
#
# Usage:
#   fetch-datasets.sh [options]
#     --prefix DIR     Geant4 install prefix.  Datasets go to
#                      DIR/share/Geant4/data and the environment file to
#                      DIR/bin/geant4-datasets.{sh,csh}.  Default: derived from
#                      the location of this script, else /usr/local/geant4.
#     --data-dir DIR   Override the dataset directory alone.
#     --env-dir DIR    Override where the environment files are written.
#                      Pass "none" to write none.
#     --table FILE     Dataset table.  Default: datasets.tsv beside this script.
#     --all            Install every dataset in the table.
#     --required       Install only the datasets marked required (the default).
#     --only LIST      Install exactly these, comma or space separated.  Each
#                      entry may be the directory (G4EMLOW8.8), the variable
#                      (G4LEDATA) or the stem (G4EMLOW).
#     --url BASE       Base URL.  Default: https://cern.ch/geant4-data/datasets
#     --keep-archives  Do not delete the downloaded tarballs.
#     --no-verify      Skip the MD5 check (not recommended).
#     --force          Re-download and re-extract datasets already present.
#     --quiet          Only report failures.
#
# Exit status is 0 if every selected dataset ended up installed, 1 otherwise.
# A dataset that fails to download is reported and skipped; the others still
# get installed, and the environment file still lists only what is really
# there.  A half-extracted directory is never left behind: extraction happens
# into a scratch directory and is moved into place only once it has succeeded.

set -u

self=$(cd "$(dirname "$0")" && pwd)

prefix=
data_dir=
env_dir=
table=$self/datasets.tsv
selection=required
only=
base_url=https://cern.ch/geant4-data/datasets
keep_archives=0
verify=1
force=0
quiet=0

while [ $# -gt 0 ]; do
    case $1 in
        --prefix)        prefix=$2; shift 2 ;;
        --data-dir)      data_dir=$2; shift 2 ;;
        --env-dir)       env_dir=$2; shift 2 ;;
        --table)         table=$2; shift 2 ;;
        --all)           selection=all; shift ;;
        --required)      selection=required; shift ;;
        --only)          selection=only; only=$2; shift 2 ;;
        --url)           base_url=$2; shift 2 ;;
        --keep-archives) keep_archives=1; shift ;;
        --no-verify)     verify=0; shift ;;
        --force)         force=1; shift ;;
        --quiet)         quiet=1; shift ;;
        -h|--help)       sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "fetch-datasets.sh: unknown option $1" >&2; exit 2 ;;
    esac
done

say() { [ "$quiet" -eq 1 ] || echo "$@"; }
fail() { echo "fetch-datasets.sh: $*" >&2; }

# ---------------------------------------------------------------------------
# Where things go
# ---------------------------------------------------------------------------

if [ -z "$prefix" ]; then
    # Installed as <prefix>/share/Geant4/fetch-datasets.sh, or run from the
    # source tree next to datasets.tsv.
    if [ -d "$self/../../bin" ] && [ -x "$self/../../bin/geant4-config" ]; then
        prefix=$(cd "$self/../.." && pwd)
    else
        prefix=/usr/local/geant4
    fi
fi

[ -n "$data_dir" ] || data_dir=$prefix/share/Geant4/data
[ -n "$env_dir" ]  || env_dir=$prefix/bin

if [ ! -r "$table" ]; then
    fail "dataset table not found: $table"
    exit 1
fi

# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

if command -v curl >/dev/null 2>&1; then
    download() { curl -sSL -f --retry 3 --retry-delay 5 --max-time 3600 -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
    download() { wget -q --tries=3 --timeout=3600 -O "$2" "$1"; }
else
    fail "neither curl nor wget is available"
    exit 1
fi

# md5sum on Linux, md5 -q on macOS/BSD.  Without either, verification is off.
if command -v md5sum >/dev/null 2>&1; then
    md5of() { md5sum "$1" | cut -d' ' -f1; }
elif command -v md5 >/dev/null 2>&1; then
    md5of() { md5 -q "$1"; }
else
    [ "$verify" -eq 1 ] && fail "no md5sum or md5 found, skipping verification"
    verify=0
    md5of() { echo ""; }
fi

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

# wanted <dir> <var> <required> -> 0 if this dataset should be installed
wanted() {
    _dir=$1; _var=$2; _req=$3
    case $selection in
        all)      return 0 ;;
        required) [ "$_req" = "1" ] && return 0; return 1 ;;
        only)
            # Strip the trailing version from the directory to get the stem:
            # G4EMLOW8.8 -> G4EMLOW, PhotonEvaporation6.1.2 -> PhotonEvaporation
            _stem=$(printf '%s' "$_dir" | sed 's/[0-9][0-9.]*$//')
            for _w in $(printf '%s' "$only" | tr ',' ' '); do
                [ "$_w" = "$_dir" ] && return 0
                [ "$_w" = "$_var" ] && return 0
                [ "$_w" = "$_stem" ] && return 0
            done
            return 1 ;;
    esac
    return 1
}

# ---------------------------------------------------------------------------
# Install one dataset
# ---------------------------------------------------------------------------

tmp=${TMPDIR:-/tmp}/geant4-datasets.$$
mkdir -p "$tmp" || { fail "cannot create $tmp"; exit 1; }
cleanup() { [ "$keep_archives" -eq 1 ] || rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

mkdir -p "$data_dir" || { fail "cannot create $data_dir"; exit 1; }

failed=0
installed=

install_one() {
    _dir=$1; _archive=$2; _md5=$3

    if [ -d "$data_dir/$_dir" ] && [ "$force" -eq 0 ]; then
        say "  $_dir: already present"
        return 0
    fi

    _tarball=$tmp/$_archive
    if [ -f "$_tarball" ] && [ "$force" -eq 0 ]; then
        say "  $_dir: using cached $_archive"
    else
        say "  $_dir: downloading $_archive"
        if ! download "$base_url/$_archive" "$_tarball"; then
            fail "$_dir: download failed ($base_url/$_archive)"
            rm -f "$_tarball"
            return 1
        fi
    fi

    if [ "$verify" -eq 1 ]; then
        _got=$(md5of "$_tarball")
        if [ "$_got" != "$_md5" ]; then
            fail "$_dir: MD5 mismatch (got $_got, expected $_md5), discarded"
            rm -f "$_tarball"
            return 1
        fi
    fi

    # Extract into a scratch directory first, so a failure cannot leave a
    # partial dataset that later looks installed.
    _stage=$tmp/stage.$_dir
    rm -rf "$_stage"
    mkdir -p "$_stage"
    if ! tar xzf "$_tarball" -C "$_stage"; then
        fail "$_dir: extraction failed"
        rm -rf "$_stage"
        return 1
    fi
    if [ ! -d "$_stage/$_dir" ]; then
        fail "$_dir: archive did not contain a directory named $_dir"
        rm -rf "$_stage"
        return 1
    fi

    rm -rf "$data_dir/$_dir"
    if ! mv "$_stage/$_dir" "$data_dir/$_dir"; then
        fail "$_dir: could not move into $data_dir"
        rm -rf "$_stage"
        return 1
    fi
    rm -rf "$_stage"
    [ "$keep_archives" -eq 1 ] || rm -f "$_tarball"
    say "  $_dir: installed"
    return 0
}

say "Geant4 datasets -> $data_dir"

# The table is read into a here-string-free loop; a pipe would put the loop in a
# subshell and lose the counters.
rows=$(grep -v '^[[:space:]]*#' "$table" | grep -v '^[[:space:]]*$')
oldifs=$IFS
IFS='
'
for row in $rows; do
    IFS='	'
    # shellcheck disable=SC2086
    set -- $row
    IFS=$oldifs
    dir=$1; var=$2; archive=$3; md5=$4; req=$5
    if wanted "$dir" "$var" "$req"; then
        if install_one "$dir" "$archive" "$md5"; then
            installed="$installed $var"
        else
            failed=$((failed + 1))
        fi
    fi
    IFS='
'
done
IFS=$oldifs

# ---------------------------------------------------------------------------
# Environment file
# ---------------------------------------------------------------------------
#
# Geant4 11's own geant4.sh exports GEANT4_DATA_DIR and leaves the twelve
# per-dataset variables commented out.  Most code copes, but anything that
# looks a variable up directly (Strata's front end among it) does not, so
# both are written here.  Only datasets that are actually on disk are listed,
# which is what makes the file safe to regenerate after adding one.

write_env() {
    _sh=$env_dir/geant4-datasets.sh
    _csh=$env_dir/geant4-datasets.csh

    mkdir -p "$env_dir" || { fail "cannot create $env_dir"; return 1; }

    {
        echo "# Geant4 dataset locations.  Written by fetch-datasets.sh, regenerate"
        echo "# rather than edit; any dataset added later will be picked up."
        echo "GEANT4_DATA_DIR=\"$data_dir\"; export GEANT4_DATA_DIR"
    } > "$_sh"
    {
        echo "# Geant4 dataset locations.  Written by fetch-datasets.sh."
        echo "setenv GEANT4_DATA_DIR \"$data_dir\""
    } > "$_csh"

    IFS='
'
    for row in $rows; do
        IFS='	'
        # shellcheck disable=SC2086
        set -- $row
        IFS=$oldifs
        if [ -d "$data_dir/$1" ]; then
            echo "$2=\"$data_dir/$1\"; export $2" >> "$_sh"
            echo "setenv $2 \"$data_dir/$1\"" >> "$_csh"
        fi
        IFS='
'
    done
    IFS=$oldifs

    say "Environment written to $_sh and $_csh"
}

if [ "$env_dir" != "none" ]; then
    write_env
fi

if [ "$failed" -gt 0 ]; then
    fail "$failed dataset(s) could not be installed; see above"
    fail "re-run this script to retry just those, or download them by hand from"
    fail "$base_url and extract them into $data_dir"
    exit 1
fi

say "All selected datasets are installed."
exit 0
