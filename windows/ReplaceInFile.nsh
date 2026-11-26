; _ReplaceInFile SOURCE_FILE SEARCH_TEXT REPLACEMENT
;
; The macro of the NSIS wiki header of the same name, with the work done by
; Windows PowerShell on the whole file.  The wiki version reads 1023 characters
; at a time and passes each piece through StrRep, which is also limited to 1024:
; geant4-config and Geant4Config.cmake have lines of 1700 characters with seven
; prefixes in the first piece, and a longer install path pushes it past the
; limit, so the end of the piece is silently cut off.
;
; The text is replaced literally (not as a pattern), bytes are kept as they are,
; and a file that does not exist is skipped.  $R9 is preserved.

!ifndef REPLACEINFILE_NSH
!define REPLACEINFILE_NSH
!include LogicLib.nsh

!macro _ReplaceInFile SOURCE_FILE SEARCH_TEXT REPLACEMENT
  ${If} ${FileExists} "${SOURCE_FILE}"
    Push $R9
    nsExec::ExecToLog `"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$$f='${SOURCE_FILE}'; $$e=[Text.Encoding]::GetEncoding(28591); [IO.File]::WriteAllBytes($$f, $$e.GetBytes($$e.GetString([IO.File]::ReadAllBytes($$f)).Replace('${SEARCH_TEXT}', '${REPLACEMENT}')))"`
    Pop $R9
    DetailPrint "${SOURCE_FILE}: ${SEARCH_TEXT} -> ${REPLACEMENT} (exit $R9)"
    Pop $R9
  ${EndIf}
!macroend

!endif
