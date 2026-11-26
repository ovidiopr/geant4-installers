#!/bin/sh
#
# Build a macOS installer package for Geant4.
#
#   ./build-pkg.sh --source /path/to/geant4-install --version 11.4.3
#
# The result is Install_Geant4-<version>.pkg: a distribution package whose
# component list is the Windows installer's component page in macOS form --
# the Geant4 tree itself, one tick box per dataset, and two tick boxes for the
# environment.  The dataset boxes are payload-free packages whose postinstall
# runs ../fetch-datasets.sh, so the datasets are downloaded and configured
# while the package installs, exactly as inetc/untgz/EnVar do on Windows.
#
# --source must be a finished Geant4 installation (bin/ include/ lib/ share/),
# i.e. the result of `cmake --install`.  It does not need to have been
# configured for the destination prefix: the absolute paths Geant4 bakes into
# geant4-config, geant4.sh, geant4.csh and the CMake files are rewritten by the
# core postinstall, which is what the Windows script's -Post section does with
# ReplaceInFile.
#
# Options:
#   --source DIR    the Geant4 installation to package     (required)
#   --version V     version string; default from geant4-config in --source
#   --prefix DIR    install destination; default /usr/local/geant4/<version>
#   --output FILE   output package; default Install_Geant4-<version>.pkg
#   --identifier ID base identifier; default org.geant4
#   --sign IDENT    Developer ID Installer identity to sign with
#   --build DIR     scratch directory; default ./build
#   --stage-only    stage the payload and generate the scripts and the
#                   distribution, but do not call pkgbuild/productbuild.  The
#                   scratch directory is then a complete, inspectable record of
#                   what the package would contain, and the postinstall scripts
#                   in it can be run by hand against a test prefix.

set -eu

here=$(cd "$(dirname "$0")" && pwd)
table=$here/../datasets.tsv
fetch=$here/../fetch-datasets.sh

source_dir=
version=
prefix=
output=
identifier=org.geant4
sign=
build=$here/build
stage_only=0

while [ $# -gt 0 ]; do
    case $1 in
        --source)     source_dir=$2; shift 2 ;;
        --version)    version=$2; shift 2 ;;
        --prefix)     prefix=$2; shift 2 ;;
        --output)     output=$2; shift 2 ;;
        --identifier) identifier=$2; shift 2 ;;
        --sign)       sign=$2; shift 2 ;;
        --build)      build=$2; shift 2 ;;
        --stage-only) stage_only=1; shift ;;
        -h|--help)    sed -n '2,/^set -eu/p' "$0" | sed 's/^# \{0,1\}//;$d'; exit 0 ;;
        *) echo "build-pkg.sh: unknown option $1" >&2; exit 2 ;;
    esac
done

[ -n "$source_dir" ] || { echo "build-pkg.sh: --source is required" >&2; exit 2; }
[ -d "$source_dir/lib" ] || { echo "build-pkg.sh: $source_dir is not a Geant4 installation" >&2; exit 2; }
[ -r "$table" ] || { echo "build-pkg.sh: dataset table not found: $table" >&2; exit 2; }

source_dir=$(cd "$source_dir" && pwd)

if [ -z "$version" ]; then
    if [ -x "$source_dir/bin/geant4-config" ]; then
        version=$("$source_dir/bin/geant4-config" --version)
    else
        echo "build-pkg.sh: --version is required (no geant4-config in --source)" >&2
        exit 2
    fi
fi

[ -n "$prefix" ] || prefix=/usr/local/geant4/$version
[ -n "$output" ] || output=$here/Install_Geant4-$version.pkg

# pkgbuild and productbuild are given these after the script has cd'd about, so
# neither may stay relative to the directory make was run in.
mkdir -p "$(dirname "$output")" "$build"
output=$(cd "$(dirname "$output")" && pwd)/$(basename "$output")
build=$(cd "$build" && pwd)

# The prefix Geant4 was configured for, so the postinstall knows what to
# rewrite.  An installation that was configured for the destination already
# produces build_prefix = prefix and the rewrite becomes a no-op.
if [ -x "$source_dir/bin/geant4-config" ]; then
    build_prefix=$("$source_dir/bin/geant4-config" --prefix)
else
    build_prefix=$source_dir
fi

echo "Geant4 $version"
echo "  source       $source_dir"
echo "  built for    $build_prefix"
echo "  installs to  $prefix"
echo "  output       $output"

rm -rf "$build"
mkdir -p "$build/pkgs" "$build/root" "$build/resources"

# ---------------------------------------------------------------------------
# Core package: the tree, plus the dataset machinery it will need later
# ---------------------------------------------------------------------------

echo "Staging the tree..."
# tar rather than cp, to keep the symlinks (lib/libG4*.dylib are versioned)
# and the permissions.
# The datasets are NOT packaged, even when --source has them installed: they
# are two gigabytes, the whole design is that the installer downloads only the
# ones the user asked for, and the package description says they are not in
# here. An empty data/ goes in so the directory exists and is owned.
( cd "$source_dir" && tar cf - --exclude ./share/Geant4/data . ) \
    | ( cd "$build/root" && tar xf - )
mkdir -p "$build/root/share/Geant4/data"

# fetch-datasets.sh and its table travel with the installation so that the
# dataset packages can run them, and so the user can add a dataset afterwards
# without the installer.
mkdir -p "$build/root/share/Geant4"
cp "$fetch" "$table" "$build/root/share/Geant4/"
chmod 755 "$build/root/share/Geant4/fetch-datasets.sh"
cp "$here/geant4-setenv-launchd.sh" "$build/root/share/Geant4/"
chmod 755 "$build/root/share/Geant4/geant4-setenv-launchd.sh"
sed -e "s|@PREFIX@|$prefix|g" -e "s|@VERSION@|$version|g" \
    "$here/uninstall-geant4.sh.in" > "$build/root/bin/uninstall-geant4.sh"
chmod 755 "$build/root/bin/uninstall-geant4.sh"

mkdir -p "$build/scripts/core"
sed -e "s|@PREFIX@|$prefix|g" \
    -e "s|@BUILD_PREFIX@|$build_prefix|g" \
    -e "s|@VERSION@|$version|g" \
    "$here/scripts/core-postinstall.in" > "$build/scripts/core/postinstall"
chmod 755 "$build/scripts/core/postinstall"

if [ "$stage_only" -eq 0 ]; then
pkgbuild --quiet \
         --root "$build/root" \
         --install-location "$prefix" \
         --scripts "$build/scripts/core" \
         --identifier "$identifier.core" \
         --version "$version" \
         "$build/pkgs/core.pkg"
fi
echo "  core.pkg"

# ---------------------------------------------------------------------------
# One payload-free package per dataset
# ---------------------------------------------------------------------------

choices_datasets=
refs=

while IFS='	' read -r dir var archive md5 required desc; do
    case $dir in \#*|'') continue ;; esac
    [ -n "$var" ] || continue

    id=$identifier.data.$(printf '%s' "$var" | tr 'A-Z' 'a-z')
    sdir=$build/scripts/data-$var
    mkdir -p "$sdir"
    sed -e "s|@PREFIX@|$prefix|g" -e "s|@DATASET@|$dir|g" \
        "$here/scripts/dataset-postinstall.in" > "$sdir/postinstall"
    chmod 755 "$sdir/postinstall"

    if [ "$stage_only" -eq 0 ]; then
        pkgbuild --quiet --nopayload \
                 --scripts "$sdir" \
                 --identifier "$id" \
                 --version "$version" \
                 "$build/pkgs/data-$var.pkg"
    else
        : > "$build/pkgs/data-$var.pkg"
    fi

    # Every dataset starts selected; the description says which are required
    sel=true
    [ "$required" = "1" ] && desc="$desc (required: Geant4 cannot run without it)"

    choices_datasets="$choices_datasets
        <line choice=\"$id\"/>"
    refs="$refs
    <choice id=\"$id\" visible=\"true\" start_selected=\"$sel\" title=\"$dir\" description=\"$desc\">
        <pkg-ref id=\"$id\"/>
    </choice>
    <pkg-ref id=\"$id\" version=\"$version\" onConclusion=\"none\">data-$var.pkg</pkg-ref>"
done < "$table"
echo "  $(ls "$build/pkgs" | grep -c '^data-') dataset packages, all selected by default"

# ---------------------------------------------------------------------------
# Environment packages
# ---------------------------------------------------------------------------
#
# Two of them, because macOS has two unrelated environments and the Windows
# installer's single EnVar call covers both.  A login shell reads /etc/zprofile
# or /etc/profile; an application launched from the Finder or the Dock reads
# neither, and sees only what launchctl has been told.  Graphical programs are
# the second case, so both default to selected.

for part in shell agent; do
    sdir=$build/scripts/env-$part
    mkdir -p "$sdir"
    sed -e "s|@PREFIX@|$prefix|g" -e "s|@VERSION@|$version|g" \
        "$here/scripts/env-$part-postinstall.in" > "$sdir/postinstall"
    chmod 755 "$sdir/postinstall"
    if [ "$stage_only" -eq 0 ]; then
        pkgbuild --quiet --nopayload \
                 --scripts "$sdir" \
                 --identifier "$identifier.env.$part" \
                 --version "$version" \
                 "$build/pkgs/env-$part.pkg"
    else
        : > "$build/pkgs/env-$part.pkg"
    fi
done
echo "  env-shell.pkg env-agent.pkg"

# ---------------------------------------------------------------------------
# Distribution
# ---------------------------------------------------------------------------

sed -e "s|@VERSION@|$version|g" -e "s|@PREFIX@|$prefix|g" \
    "$here/resources/welcome.html.in" > "$build/resources/welcome.html"
sed -e "s|@VERSION@|$version|g" -e "s|@PREFIX@|$prefix|g" \
    "$here/resources/conclusion.html.in" > "$build/resources/conclusion.html"

cat > "$build/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Geant4 $version</title>
    <organization>$identifier</organization>
    <options customize="always" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <volume-check>
        <allowed-os-versions><os-version min="11.0"/></allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="$identifier.core"/>
        <line choice="datasets">$choices_datasets
        </line>
        <line choice="environment">
            <line choice="$identifier.env.shell"/>
            <line choice="$identifier.env.agent"/>
        </line>
    </choices-outline>

    <choice id="$identifier.core" visible="true" start_selected="true" start_enabled="false"
            title="Geant4 $version" description="The Geant4 libraries, headers and tools.">
        <pkg-ref id="$identifier.core"/>
    </choice>
    <pkg-ref id="$identifier.core" version="$version" onConclusion="none">core.pkg</pkg-ref>

    <choice id="datasets" title="Data files"
            description="Download and install the Geant4 datasets. All are selected by default; untick the ones you do not need. The seven marked as required are the ones Geant4 cannot run without."/>
$refs

    <choice id="environment" title="Environment"
            description="Make the datasets visible to programs that use them."/>
    <choice id="$identifier.env.shell" visible="true" start_selected="true"
            title="Command-line environment"
            description="Add $prefix/bin to the path and have login shells read the dataset variables.">
        <pkg-ref id="$identifier.env.shell"/>
    </choice>
    <pkg-ref id="$identifier.env.shell" version="$version" onConclusion="none">env-shell.pkg</pkg-ref>
    <choice id="$identifier.env.agent" visible="true" start_selected="true"
            title="Application environment"
            description="Install a login agent so applications started from the Finder or the Dock also see the dataset variables.">
        <pkg-ref id="$identifier.env.agent"/>
    </choice>
    <pkg-ref id="$identifier.env.agent" version="$version" onConclusion="none">env-agent.pkg</pkg-ref>
</installer-gui-script>
XML

if [ "$stage_only" -eq 1 ]; then
    echo
    echo "Staged in $build; no package built (--stage-only)."
    echo "  distribution.xml, pkgs/, scripts/, root/ are all there to inspect."
    exit 0
fi

echo "Building the distribution..."
set -- --quiet \
       --distribution "$build/distribution.xml" \
       --package-path "$build/pkgs" \
       --resources "$build/resources"
[ -n "$sign" ] && set -- "$@" --sign "$sign"
productbuild "$@" "$output"

echo
echo "Wrote $output ($(du -h "$output" | cut -f1))"
echo
echo "The datasets are not in the package -- they are downloaded while it"
echo "installs, so the machine needs to reach cern.ch at that moment."
