#!/bin/sh
#
# Static checks on Geant4.nsi and the generated datasets.nsh.
#
# makensis only exists on Windows, so the script cannot be compiled on the
# machine it is usually edited on.  This checks the structure that editing
# actually breaks: unbalanced blocks, a description naming a section that does
# not exist, an !insertmacro with no !macro, a ${DEFINE} that was never
# defined, and a dataset in the table with no section or the other way round.
#
# It is not a compiler.  It will not catch a bad plugin call or a wrong
# argument; a build on Windows is still the real test.
#
#   ./check-nsi.sh [Geant4.nsi]

set -eu

here=$(cd "$(dirname "$0")" && pwd)
nsi=${1:-$here/Geant4.nsi}
nsh=$here/datasets.nsh
table=$here/../datasets.tsv

for f in "$nsi" "$nsh" "$table"; do
    [ -r "$f" ] || { echo "check-nsi.sh: cannot read $f" >&2; exit 1; }
done

# The concatenation is what makensis effectively sees: datasets.nsh is pulled
# in by !include, so the two must be analysed together.
cat "$nsi" "$nsh" > "${TMPDIR:-/tmp}/nsi-check.$$"
trap 'rm -f "${TMPDIR:-/tmp}/nsi-check.$$"' EXIT INT TERM

awk -v table="$table" '
function strip(s) { sub(/;.*$/, "", s); return s }

# Names that come from an included header rather than from this file.  A
# leading underscore is the convention header-private macros use
# (_ReplaceInFile), and LogicLib supplies the flow-control words, which NSIS
# matches without regard to case.
function external(s,    l) {
    if (s ~ /^_/) return 1
    if (s ~ /^(MUI|MULTIUSER)_/) return 1
    l = tolower(s)
    return (l in logiclib)
}

BEGIN {
    split("if else elseif endif unless andif orif " \
          "select case caseelse endselect switch endswitch " \
          "do loop while endwhile for next foreach " \
          "break continue exitdo exitwhile exitfor", lw, " ")
    for (i in lw) logiclib[lw[i]] = 1

    # Symbols NSIS or the included headers define, which this file legitimately
    # uses without defining.
    builtin["StrRep"] = 1
    builtin["RMDirUP"] = 1
    builtin["^Name"] = 1
    while ((getline line < table) > 0) {
        if (line ~ /^#/) continue
        n = split(line, f, "\t")
        if (n < 5) continue
        want_section[f[2]] = f[1]
        n_datasets++
    }
    close(table)
}

{
    line = strip($0)

    # --- block balance ---
    if (line ~ /^[[:space:]]*Section[[:space:]]/)       sect++
    if (line ~ /^[[:space:]]*SectionEnd[[:space:]]*$/)  sect--
    if (line ~ /^[[:space:]]*SectionGroup[[:space:]]/)  grp++
    if (line ~ /^[[:space:]]*SectionGroupEnd[[:space:]]*$/) grp--
    if (line ~ /^[[:space:]]*Function[[:space:]]/)      fun++
    if (line ~ /^[[:space:]]*FunctionEnd[[:space:]]*$/) fun--
    if (line ~ /^[[:space:]]*!macro[[:space:]]/)        mac++
    if (line ~ /^[[:space:]]*!macroend[[:space:]]*$/)   mac--

    # --- definitions ---
    if (match(line, /^[[:space:]]*!define[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*/)) {
        s = substr(line, RSTART, RLENGTH)
        sub(/^[[:space:]]*!define[[:space:]]+/, "", s)
        defined[s] = 1
    }
    if (match(line, /^[[:space:]]*!macro[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*/)) {
        s = substr(line, RSTART, RLENGTH)
        sub(/^[[:space:]]*!macro[[:space:]]+/, "", s)
        macro[s] = 1
        # A macro name is also usable as ${name} nowhere, but its parameters
        # are; record them so ${DataVar} does not look undefined.
        rest = line
        sub(/^[[:space:]]*!macro[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*/, "", rest)
        np = split(rest, p, /[[:space:]]+/)
        for (i = 1; i <= np; i++) if (p[i] != "") defined[p[i]] = 1
    }

    # --- section ids ---
    # Section [/o] "title" ID   or   SectionGroup [/e] "title" ID
    if (line ~ /^[[:space:]]*Section[Gg]?[[:space:]]*/ || line ~ /^[[:space:]]*SectionGroup[[:space:]]/) {
        t = line
        if (match(t, /"[^"]*"[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*$/)) {
            s = substr(t, RSTART, RLENGTH)
            sub(/^"[^"]*"[[:space:]]+/, "", s)
            gsub(/[[:space:]]+$/, "", s)
            section_id[s] = NR
            defined[s] = 1
        }
    }
    # Section "un.Uninstall files" Uninstall -- caught by the same rule.

    # --- uses ---
    if (match(line, /^[[:space:]]*!insertmacro[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*/)) {
        s = substr(line, RSTART, RLENGTH)
        sub(/^[[:space:]]*!insertmacro[[:space:]]+/, "", s)
        used_macro[s] = used_macro[s] " " NR
    }
    rest = line
    while (match(rest, /\$\{[A-Za-z_][A-Za-z0-9_.]*\}/)) {
        s = substr(rest, RSTART + 2, RLENGTH - 3)
        used_define[s] = used_define[s] " " NR
        rest = substr(rest, RSTART + RLENGTH)
    }

    # --- description targets ---
    if (line ~ /MUI_DESCRIPTION_TEXT/) {
        if (match(line, /\$\{[A-Za-z_][A-Za-z0-9_.]*\}/)) {
            s = substr(line, RSTART + 2, RLENGTH - 3)
            described[s] = NR
        }
    }
}

END {
    if (sect != 0) { print "  FAIL  Section/SectionEnd unbalanced (" sect ")"; bad++ }
    if (grp  != 0) { print "  FAIL  SectionGroup/SectionGroupEnd unbalanced (" grp ")"; bad++ }
    if (fun  != 0) { print "  FAIL  Function/FunctionEnd unbalanced (" fun ")"; bad++ }
    if (mac  != 0) { print "  FAIL  !macro/!macroend unbalanced (" mac ")"; bad++ }

    for (m in used_macro)
        if (!(m in macro) && !(m in builtin) && !external(m)) {
            print "  FAIL  !insertmacro " m " has no !macro (line" used_macro[m] ")"; bad++
        }

    for (d in used_define)
        if (!(d in defined) && !(d in builtin) && !external(d)) {
            print "  FAIL  ${" d "} is never defined (line" used_define[d] ")"; bad++
        }

    for (d in described)
        if (!(d in section_id)) {
            print "  FAIL  description at line " described[d] " names ${" d "}, which is not a section"; bad++
        }

    # Every dataset gets exactly one section, named SEC_<variable>.
    for (v in want_section) {
        id = "SEC_" v
        if (!(id in section_id)) { print "  FAIL  no section " id " for " want_section[v]; bad++ }
        else if (!(id in described)) { print "  FAIL  section " id " has no description"; bad++ }
        else n_ok++
    }
    for (s in section_id)
        if (s ~ /^SEC_/) {
            v = substr(s, 5)
            if (!(v in want_section)) { print "  FAIL  section " s " is not in the dataset table"; bad++ }
        }

    if (bad) { print "  " bad " problem(s)"; exit 1 }
    printf "  ok      Geant4.nsi + datasets.nsh: %d sections, %d datasets matched\n", \
           length(section_id), n_ok
}
' "${TMPDIR:-/tmp}/nsi-check.$$"
