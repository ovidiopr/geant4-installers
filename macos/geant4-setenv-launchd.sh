#!/bin/sh
#
# Publish the Geant4 dataset variables into the user's launchd session, so
# that applications started from the Finder or the Dock see them.
#
#   geant4-setenv-launchd.sh [prefix]
#
# Run at every login by the LaunchAgent the installer writes, and usable by
# hand after adding a dataset:
#
#   /usr/local/geant4/11.4.3/share/Geant4/geant4-setenv-launchd.sh
#
# It reads the generated environment file rather than the dataset table, so a
# dataset that failed to download is not advertised as present -- a variable
# pointing at a directory that is not there makes Geant4 fail later and less
# clearly than no variable at all.

set -u

prefix=${1:-}
if [ -z "$prefix" ]; then
    # share/Geant4/geant4-setenv-launchd.sh -> prefix
    prefix=$(cd "$(dirname "$0")/../.." && pwd)
fi

env_file=$prefix/bin/geant4-datasets.sh
[ -r "$env_file" ] || exit 0

# The file is a list of  NAME="value"; export NAME  lines.  Parsing it is
# safer than sourcing it: this runs at login, and nothing here needs to
# execute whatever the file might contain.
sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)="\(.*\)"; export \1$/\1 \2/p' "$env_file" |
while read -r name value; do
    [ -n "$name" ] || continue
    launchctl setenv "$name" "$value" 2>/dev/null || true
done

exit 0
