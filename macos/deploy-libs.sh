#!/bin/sh
# Make a Geant4 tree self-contained: copy into it the Qt6 frameworks and
# plug-ins it links against, and every other library outside the system that
# it links by absolute path (Homebrew's Xerces-C for GDML, and what that needs).
#
#   deploy-libs.sh <geant4-install> [<qt-dir>]
#
# Frameworks and libraries go to lib/ beside the Geant4 libraries and Qt
# plug-ins to plugins/, where a relocatable Qt looks for them.  References are
# rewritten to @rpath and the changed files are signed ad hoc.

set -eu

tree=${1:?usage: deploy-libs.sh <geant4-install> [<qt-dir>]}
qt=${2:-}
lib=$tree/lib
plugins=$tree/plugins

if [ -z "$qt" ]; then
    echo "deploy-libs.sh: no Qt directory given, Qt not deployed"
else
[ -d "$qt/lib/QtCore.framework" ] || { echo "deploy-libs.sh: no Qt6 in $qt" >&2; exit 2; }
mkdir -p "$plugins"

# Qt from the Qt installer keeps its plug-ins in plugins/, Homebrew's in share/qt/plugins/
qtplugins=$qt/plugins
[ -d "$qtplugins" ] || qtplugins=$qt/share/qt/plugins

# The plug-ins a widget application with OpenGL needs
for d in platforms styles imageformats iconengines; do
    [ -d "$qtplugins/$d" ] && ditto "$qtplugins/$d" "$plugins/$d"
done

# The Qt frameworks a binary links, one per line
qt_refs() {
    otool -L "$1" | sed -n 's|^[[:space:]]*\([^ ]*/\(Qt[A-Za-z0-9]*\)\.framework/[^ ]*\) .*|\2 \1|p' | sort -u
}

# Libraries that may link Qt: the Geant4 ones and the plug-ins
targets=$( { find "$lib" -maxdepth 1 -type f -name '*.dylib'; find "$plugins" -type f -name '*.dylib'; } )

# Every framework they need, and those the frameworks need in turn
copied=" "
frameworks=
queue=$targets
while [ -n "$queue" ]; do
    next=
    for f in $queue; do
        for fw in $(qt_refs "$f" | cut -d' ' -f1); do
            case $copied in *" $fw "*) continue ;; esac
            copied="$copied$fw "
            echo "  $fw.framework"
            rm -rf "$lib/$fw.framework"
            ditto "$qt/lib/$fw.framework" "$lib/$fw.framework"
            frameworks="$frameworks $lib/$fw.framework/Versions/A/$fw"
            next="$next $lib/$fw.framework/Versions/A/$fw"
        done
    done
    queue=$next
done

# Point every Qt reference at @rpath, and give each binary the rpath that reaches lib/
for f in $targets $frameworks; do
    refs=$(qt_refs "$f")
    [ -n "$refs" ] || continue
    echo "$refs" | while read -r fw path; do
        case $path in
            @rpath/*) ;;
            *) install_name_tool -change "$path" "@rpath/$fw.framework/Versions/A/$fw" "$f" ;;
        esac
    done
    install_name_tool -delete_rpath "$qt/lib" "$f" 2>/dev/null || true
    case $f in
        "$plugins"/*)     rp=@loader_path/../../lib ;;
        *.framework/*)    rp=@loader_path/../../.. ;;
        *)                rp=@loader_path ;;
    esac
    install_name_tool -add_rpath "$rp" "$f" 2>/dev/null || true
done

# A framework names itself by @rpath too
for f in $frameworks; do
    fw=$(basename "$f")
    install_name_tool -id "@rpath/$fw.framework/Versions/A/$fw" "$f"
done

# Changed binaries have to be signed again to load on Apple silicon
for f in $targets $frameworks; do
    codesign --force --sign - "$f" 2>/dev/null || true
done

echo "deploy-libs.sh: Qt deployed into $tree"
fi

# ---------------------------------------------------------------------------
# Other libraries outside the system
# ---------------------------------------------------------------------------

# Absolute references to anything that is neither part of macOS nor a Qt
# framework, one per line
ext_refs() {
    otool -L "$1" | sed -n '2,$s|^[[:space:]]*\(/[^ ]*\) (.*|\1|p' |
        grep -v -e '^/usr/lib/' -e '^/System/' -e '\.framework/' || true
}

bundled=" "
queue=$( { find "$lib" -maxdepth 1 -type f -name '*.dylib'
           [ -d "$plugins" ] && find "$plugins" -type f -name '*.dylib'; } )
while [ -n "$queue" ]; do
    next=
    for f in $queue; do
        changed=0
        for ref in $(ext_refs "$f"); do
            name=$(basename "$ref")
            case $bundled in *" $name "*) ;; *)
                bundled="$bundled$name "
                echo "  $name"
                # The real file, not the symlink Homebrew links against
                cp -fL "$ref" "$lib/$name"
                chmod u+w "$lib/$name"
                install_name_tool -id "@rpath/$name" "$lib/$name"
                install_name_tool -add_rpath @loader_path "$lib/$name" 2>/dev/null || true
                next="$next $lib/$name" ;;
            esac
            install_name_tool -change "$ref" "@rpath/$name" "$f"
            changed=1
        done
        if [ "$changed" -eq 1 ]; then
            case $f in
                "$plugins"/*) rp=@loader_path/../../lib ;;
                *)            rp=@loader_path ;;
            esac
            install_name_tool -add_rpath "$rp" "$f" 2>/dev/null || true
            codesign --force --sign - "$f" 2>/dev/null || true
        fi
    done
    queue=$next
done
for name in $bundled; do
    codesign --force --sign - "$lib/$name" 2>/dev/null || true
done
[ "$bundled" = " " ] || echo "deploy-libs.sh: bundled$bundled"
