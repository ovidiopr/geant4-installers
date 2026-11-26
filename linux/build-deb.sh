#!/bin/sh
#
# Build a Debian package for Geant4.
#
#   ./build-deb.sh --source /path/to/geant4-install --version 11.4.3
#
# The result is geant4_<version>_<arch>.deb, which installs the tree into
# /opt/geant4/<version> and then behaves like the Windows installer: a debconf
# multiselect asks which datasets are wanted (all of them are preselected) and the postinst downloads, verifies and extracts
# them, then writes /etc/profile.d/geant4.sh so every login shell finds them.
#
# --source must be a finished Geant4 installation (bin/ include/ lib/ share/).
# As on macOS, the absolute paths Geant4 bakes into geant4-config and the CMake
# files are rewritten by the postinst, so the tree does not have to have been
# configured for /opt.
#
# Options:
#   --source DIR    the Geant4 installation to package     (required)
#   --version V     version string; default from geant4-config in --source
#   --revision N    package revision; default 1
#   --prefix DIR    install destination; default /opt/geant4/<version>
#   --arch A        Debian architecture; default from dpkg, else amd64
#   --output FILE   output file; default geant4_<version>_<arch>.deb
#   --build DIR     scratch directory; default ./build

set -eu

here=$(cd "$(dirname "$0")" && pwd)
table=$here/../datasets.tsv
fetch=$here/../fetch-datasets.sh

source_dir=
version=
revision=1
prefix=
arch=
output=
build=$here/build

while [ $# -gt 0 ]; do
    case $1 in
        --source)  source_dir=$2; shift 2 ;;
        --version) version=$2; shift 2 ;;
        --revision) revision=$2; shift 2 ;;
        --prefix)  prefix=$2; shift 2 ;;
        --arch)    arch=$2; shift 2 ;;
        --output)  output=$2; shift 2 ;;
        --build)   build=$2; shift 2 ;;
        -h|--help) sed -n '2,/^set -eu/p' "$0" | sed 's/^# \{0,1\}//;$d'; exit 0 ;;
        *) echo "build-deb.sh: unknown option $1" >&2; exit 2 ;;
    esac
done

[ -n "$source_dir" ] || { echo "build-deb.sh: --source is required" >&2; exit 2; }
[ -d "$source_dir/lib" ] || { echo "build-deb.sh: $source_dir is not a Geant4 installation" >&2; exit 2; }
source_dir=$(cd "$source_dir" && pwd)

if [ -z "$version" ]; then
    if [ -x "$source_dir/bin/geant4-config" ]; then
        version=$("$source_dir/bin/geant4-config" --version)
    else
        echo "build-deb.sh: --version is required (no geant4-config in --source)" >&2
        exit 2
    fi
fi

[ -n "$prefix" ] || prefix=/opt/geant4/$version
if [ -z "$arch" ]; then
    arch=$(dpkg --print-architecture 2>/dev/null || echo amd64)
fi
[ -n "$output" ] || output=$here/geant4_${version}-${revision}_${arch}.deb

# Both are used from inside subshells that have cd'd elsewhere, so neither may
# stay relative to the directory make was run in.
mkdir -p "$(dirname "$output")" "$build"
output=$(cd "$(dirname "$output")" && pwd)/$(basename "$output")
build=$(cd "$build" && pwd)

if [ -x "$source_dir/bin/geant4-config" ]; then
    build_prefix=$("$source_dir/bin/geant4-config" --prefix)
else
    build_prefix=$source_dir
fi

echo "Geant4 $version ($arch)"
echo "  source       $source_dir"
echo "  built for    $build_prefix"
echo "  installs to  $prefix"
echo "  output       $output"

root=$build/root
rm -rf "$build"
mkdir -p "$root/DEBIAN" "$root$prefix" "$root/usr/share/doc/geant4"

echo "Staging the tree..."
# The datasets are NOT packaged, even when --source has them installed: they
# are two gigabytes, the whole design is that the installer downloads only the
# ones the user asked for, and the package description says they are not in
# here. An empty data/ goes in so the directory exists and is owned.
( cd "$source_dir" && tar cf - --exclude ./share/Geant4/data . ) \
    | ( cd "$root$prefix" && tar xf - )
mkdir -p "$root$prefix/share/Geant4/data"

mkdir -p "$root$prefix/share/Geant4"
cp "$fetch" "$table" "$root$prefix/share/Geant4/"
chmod 755 "$root$prefix/share/Geant4/fetch-datasets.sh"

# Default dataset selection for the debconf question, and the full list of
# choices, both straight out of the table.
choices=$(awk -F'\t' '!/^#/ && NF>=5 { printf "%s%s", sep, $1; sep=", " }' "$table")
defaults=$choices

subst() {
    sed -e "s|@PREFIX@|$prefix|g" \
        -e "s|@BUILD_PREFIX@|$build_prefix|g" \
        -e "s|@VERSION@|$version|g" \
        -e "s|@REVISION@|$revision|g" \
        -e "s|@ARCH@|$arch|g" \
        -e "s|@CHOICES@|$choices|g" \
        -e "s|@DEFAULTS@|$defaults|g" \
        "$1"
}

for f in control templates config postinst prerm postrm; do
    subst "$here/debian/$f.in" > "$root/DEBIAN/$f"
done
chmod 644 "$root/DEBIAN/control" "$root/DEBIAN/templates"
chmod 755 "$root/DEBIAN/config" "$root/DEBIAN/postinst" "$root/DEBIAN/prerm" "$root/DEBIAN/postrm"

# Installed-Size, in kilobytes, as policy wants it.
size=$(du -sk "$root$prefix" | cut -f1)
printf 'Installed-Size: %s\n' "$size" >> "$root/DEBIAN/control"

subst "$here/debian/copyright.in" > "$root/usr/share/doc/geant4/copyright"

if command -v dpkg-deb >/dev/null 2>&1; then
    echo "Building with dpkg-deb..."
    if command -v fakeroot >/dev/null 2>&1; then
        fakeroot dpkg-deb --build "$root" "$output"
    else
        # Without fakeroot the files would belong to the build user
        dpkg-deb --root-owner-group --build "$root" "$output"
    fi
else
    # A .deb is an ar archive of exactly three members in a fixed order.
    # Building it by hand lets the package be produced on a machine without
    # dpkg (a macOS laptop, say) which is the only way to test this script
    # outside a Debian container.  dpkg-deb is still preferred when it exists:
    # it validates the control fields, which this does not.
    #
    # The ar(1) on the machine is not used.  BSD ar inserts a __.SYMDEF member
    # and GNU ar can rewrite names into a string table; either produces an
    # archive dpkg rejects.  The format is a 8-byte magic followed by 60-byte
    # fixed-width headers, so it is written directly.
    echo "dpkg-deb not found; assembling the archive directly..."
    stage=$build/ar
    mkdir -p "$stage"
    printf '2.0\n' > "$stage/debian-binary"
    ( cd "$root/DEBIAN" && tar czf "$stage/control.tar.gz" --format ustar . )
    ( cd "$root" && tar czf "$stage/data.tar.gz" --format ustar \
        --exclude ./DEBIAN . )

    rm -f "$output"
    printf '!<arch>\n' > "$output"
    for member in debian-binary control.tar.gz data.tar.gz; do
        bytes=$(wc -c < "$stage/$member" | tr -d ' ')
        # name(16) mtime(12) uid(6) gid(6) mode(8) size(10) magic(2)
        printf '%-16s%-12d%-6d%-6d%-8s%-10d\140\n' \
               "$member" 0 0 0 100644 "$bytes" >> "$output"
        cat "$stage/$member" >> "$output"
        # Members are padded to an even length with a newline.
        [ $((bytes % 2)) -eq 0 ] || printf '\n' >> "$output"
    done
fi

echo
echo "Wrote $output ($(du -h "$output" | cut -f1))"
echo
echo "The datasets are not in the package: debconf asks which are wanted and"
echo "the postinst downloads them, so the machine needs to reach cern.ch while"
echo "it installs.  To install non-interactively with the defaults:"
echo "  sudo DEBIAN_FRONTEND=noninteractive apt-get install ./$(basename "$output")"
