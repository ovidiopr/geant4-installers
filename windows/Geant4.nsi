; Geant4 11.4.3 installer for Windows: the local build with Qt6.
;
; Packages the build in D:\Ovidio\Computacion\Geant4\G4-11.4.3 (MSVC 2019, Qt
; 6.7.3 msvc2019_64, multithreaded), after it has been installed to a staging
; folder and Qt has been deployed into its bin with windeployqt.  The datasets
; are NOT packaged: the ones chosen on the component page are downloaded during
; the installation, the seven Geant4 aborts without preselected.  The Visual C++
; runtime is installed from Microsoft's redistributable.  The environment is
; written to the registry with EnVar: GEANT4_DATA_DIR, one variable per dataset,
; QT_PLUGIN_PATH and, optionally, PATH.
;
; Before building, once per Geant4 build (see README-Windows.md):
;   cmake --install D:\Ovidio\Computacion\Geant4\G4-11.4.3 --config Release
;         --prefix D:\Ovidio\Computacion\Geant4\G4-11.4.3-stage
;   C:\Qt\6.7.3\msvc2019_64\bin\windeployqt.exe --release --no-translations
;         --dir <stage>\bin <stage>\bin\G4interfaces.dll <stage>\bin\G4OpenGL.dll
;         <stage>\bin\G4ToolsSG.dll
; Build:
;   makensis /INPUTCHARSET UTF8 Geant4.nsi
;
; G4_TREE       the staging folder (bin, include, lib, share)
; G4_BUILD_DIR  CMAKE_INSTALL_PREFIX the build was configured with, spelt as
;               geant4-config spells it; -Post rewrites it to the install folder
; VCREDIST      vc_redist.x64.exe matching the compiler
; APP_VERSION   the Geant4 version
;
; Plug-ins: inetc, untgz, EnVar (Unicode builds).  ReplaceInFile.nsh is the one
; beside this script.  datasets.nsh is generated from ../datasets.tsv by
; gen-datasets-nsh.sh.  The archives are not checked against their MD5.

Unicode True

; HM NIS Edit Wizard helper defines
!define APP_NAME "Geant4"
!define APP_PUBLISHER "Ovidio Peña Rodríguez"
!define UNINSTALL_FILENAME "uninstall.exe"

; Everything below can be overridden on the makensis command line, which is
; what the release workflow does:
;   makensis /DAPP_VERSION=11.4.3 /DG4_BUILD_DIR=C:\g4 Geant4.nsi
!ifndef APP_VERSION
  !define APP_VERSION "11.4.3"
!endif

; The staging folder cmake --install wrote: bin, include, lib and share.  Its
; share\Geant4\data, which GEANT4_INSTALL_DATA=ON fills, is left out.
!ifndef G4_TREE
  !define G4_TREE "D:\Ovidio\Computacion\Geant4\G4-11.4.3-stage"
!endif

; Microsoft's redistributable for the MSVC 2019 (v142) toolset that built both
; Geant4 and Qt 6.7.3 msvc2019_64
!ifndef VCREDIST
  !define VCREDIST "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Redist\MSVC\14.29.30133\vc_redist.x64.exe"
!endif

; What makensis would otherwise only find out halfway, or not at all
!if ! /FileExists "${G4_TREE}\bin\G4global.dll"
  !error "No Geant4 in ${G4_TREE}: run cmake --install --config Release --prefix ${G4_TREE} first"
!endif
!if ! /FileExists "${G4_TREE}\bin\Qt6Core.dll"
  !error "No Qt in ${G4_TREE}\bin: run windeployqt on it first (see the header of this script)"
!endif
!if ! /FileExists "${G4_TREE}\bin\platforms\qwindows.dll"
  !error "No Qt platform plug-in in ${G4_TREE}\bin\platforms: run windeployqt with --dir ${G4_TREE}\bin"
!endif
!if ! /FileExists "${VCREDIST}"
  !error "No ${VCREDIST}: pass /DVCREDIST=<path to vc_redist.x64.exe>"
!endif

; CMAKE_INSTALL_PREFIX of the build, so -Post can point the paths baked into
; geant4-config and Geant4Config.cmake at wherever the user installed.  It is
; the configured prefix, not the staging one: cmake --install --prefix does not
; regenerate those files.  Spelt as CMake writes it, with forward slashes.  It
; is also compiled into the Geant4 DLLs as the last place to look for data,
; which GEANT4_DATA_DIR and the per-dataset variables set below take
; precedence over.
!ifndef G4_BUILD_DIR
  !define G4_BUILD_DIR "C:/Program Files (x86)/Geant4"
!endif

; Geant4 11 layout.  Both are relative to $INSTDIR.
!define G4_SHARE_DIR "share\${APP_NAME}"
!define G4_CMAKE_DIR "lib\cmake\${APP_NAME}"
!define G4_DATA_DIR "${G4_SHARE_DIR}\data"

SetCompressor bzip2

BrandingText "${APP_NAME}-${APP_VERSION} installer - ©2026 Ovidio Y. Peña Rodríguez"

Name "${APP_NAME} v${APP_VERSION}"
OutFile "Install_${APP_NAME}-${APP_VERSION}.exe"
ShowInstDetails show
ShowUnInstDetails show

; Configure multi-user macro
!define MULTIUSER_EXECUTIONLEVEL Highest
; Suggested name of directory to install (under $PROGRAMFILES or $LOCALAPPDATA)
!define MULTIUSER_INSTALLMODE_INSTDIR "${APP_NAME}\${APP_NAME}-${APP_VERSION}"
; Registry key for INSTALL info, placed under [HKLM|HKCU]\Software
!define MULTIUSER_INSTALLMODE_INSTALL_REGISTRY_KEY "${APP_NAME}"
!define MULTIUSER_INSTALLMODE_DEFAULT_REGISTRY_VALUENAME "UninstallString"
!define MULTIUSER_INSTALLMODE_INSTDIR_REGISTRY_VALUENAME "InstallLocation"
; Name that will be displayed in add/remove programs
!define MULTIUSER_INSTALLMODE_DISPLAYNAME "${APP_NAME} v${APP_VERSION} (${APP_PUBLISHER})"
; Allow requesting for elevation
!define MULTIUSER_INSTALLMODE_ALLOW_ELEVATION
; By default select installation for current user
!define MULTIUSER_INSTALLMODE_DEFAULT_CURRENTUSER
; Enables the installation mode to be set from the command line
!define MULTIUSER_INSTALLMODE_COMMANDLINE
; The files are for 64 bits
!define MULTIUSER_USE_PROGRAMFILES64

!define MULTIUSER_MUI
!include MultiUser.nsh
!include MUI2.nsh
!include LogicLib.nsh
!include ReplaceInFile.nsh
!include StrFunc.nsh
# Declare used functions
${StrRep}

; MUI Settings
!define MUI_ABORTWARNING
; Each is used when it is beside this script; NSIS's own otherwise
!if /FileExists "g4_32.ico"
  !define MUI_ICON "g4_32.ico"
  !define G4_HAVE_ICON
!endif
!if /FileExists "g4_32_un.ico"
  !define MUI_UNICON "g4_32_un.ico"
!endif
!if /FileExists "g4.bmp"
  !define MUI_HEADERIMAGE
  !define MUI_HEADERIMAGE_BITMAP "g4.bmp"
  !define MUI_HEADERIMAGE_RIGHT
!endif

; Installer pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MULTIUSER_PAGE_INSTALLMODE
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

; Uninstaller pages
!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_COMPONENTS
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; Language files
!insertmacro MUI_LANGUAGE "English"

; MUI end ------

!define MULTIUSER_INST_KEY "Software\${MULTIUSER_INSTALLMODE_INSTALL_REGISTRY_KEY}"
!define MULTIUSER_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${MULTIUSER_INSTALLMODE_INSTALL_REGISTRY_KEY}"

;-----------------------------------------------------------------------------
; Helpers
;-----------------------------------------------------------------------------

; Point EnVar at the hive that matches the installation mode.
!macro SelectEnvHive
  ${If} $MultiUser.InstallMode == "CurrentUser"
    EnVar::SetHKCU
  ${Else}
    EnVar::SetHKLM
  ${EndIf}
!macroend

Section "!${APP_NAME}" SEC01
  SetOutPath "$INSTDIR\bin"
  SetOverwrite try
  File /r "${G4_TREE}\bin\*"

  SetOutPath "$INSTDIR\include"
  SetOverwrite try
  File /r "${G4_TREE}\include\*"

  SetOutPath "$INSTDIR\lib"
  SetOverwrite try
  File /r "${G4_TREE}\lib\*"

  ; share\Geant4 without data: the datasets are downloaded below.  Named one by
  ; one rather than with /x, which would also drop every examples\...\data
  SetOutPath "$INSTDIR\${G4_SHARE_DIR}"
  SetOverwrite try
  File /nonfatal "${G4_TREE}\${G4_SHARE_DIR}\*.*"
!if /FileExists "${G4_TREE}\${G4_SHARE_DIR}\examples\*.*"
  File /r "${G4_TREE}\${G4_SHARE_DIR}\examples"
!endif
!if /FileExists "${G4_TREE}\${G4_SHARE_DIR}\fonts\*.*"
  File /r "${G4_TREE}\${G4_SHARE_DIR}\fonts"
!endif
!if /FileExists "${G4_TREE}\${G4_SHARE_DIR}\geant4make\*.*"
  File /r "${G4_TREE}\${G4_SHARE_DIR}\geant4make"
!endif

!ifdef G4_HAVE_ICON
  SetOutPath "$INSTDIR\share"
  File "g4_32.ico"
!endif

  ; The data directory has to exist before any dataset section runs, and has
  ; to be there even if none was selected so GEANT4_DATA_DIR points somewhere.
  CreateDirectory "$INSTDIR\${G4_DATA_DIR}"

  ; Replaced, not appended to: AddValue on an existing variable makes a list
  !insertmacro SelectEnvHive
  EnVar::Delete "GEANT4_DATA_DIR"
  Pop $0
  EnVar::AddValue "GEANT4_DATA_DIR" "$INSTDIR\${G4_DATA_DIR}"
  Pop $0
  DetailPrint "GEANT4_DATA_DIR -> $INSTDIR\${G4_DATA_DIR} (EnVar returned |$0|)"

  ; Qt looks for its plug-ins beside the executable, and a program built on
  ; Geant4 lives somewhere else: without this, the Qt session stops with "no Qt
  ; platform plugin could be initialized".  windeployqt put them in bin
  EnVar::Delete "QT_PLUGIN_PATH"
  Pop $0
  EnVar::AddValue "QT_PLUGIN_PATH" "$INSTDIR\bin"
  Pop $0
  DetailPrint "QT_PLUGIN_PATH -> $INSTDIR\bin (EnVar returned |$0|)"

  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME} Dir.lnk" "$INSTDIR"

  SectionIn RO
SectionEnd

; Qt 6.7.3 is in bin already: windeployqt copied it into the staging tree
Section "Visual C++ runtime" SEC02
  ; Run from the plug-ins directory, which NSIS deletes when the installer ends
  InitPluginsDir
  File "/oname=$PLUGINSDIR\vc_redist.x64.exe" "${VCREDIST}"
  DetailPrint "Installing the Visual C++ runtime..."
  ExecWait '"$PLUGINSDIR\vc_redist.x64.exe" /install /quiet /norestart' $0
  ; 1638: a newer one is installed already; 3010: done, a restart completes it
  ${If} $0 == 0
    DetailPrint "Visual C++ runtime installed"
  ${ElseIf} $0 == 1638
    DetailPrint "Visual C++ runtime: a newer version is already installed"
  ${ElseIf} $0 == 3010
    DetailPrint "Visual C++ runtime installed; Windows needs a restart to finish"
    SetRebootFlag true
  ${Else}
    DetailPrint "Visual C++ runtime: vc_redist.x64.exe returned $0"
    MessageBox MB_ICONEXCLAMATION|MB_OK "The Visual C++ runtime could not be installed (code $0). Geant4 needs it: install vc_redist.x64.exe from Microsoft."
  ${EndIf}
SectionEnd

Section /o "Add to PATH" SEC03
  !insertmacro SelectEnvHive
  EnVar::AddValue "path" "$INSTDIR\bin"
  Pop $0
  DetailPrint "EnVar::AddValue returned=|$0|"
SectionEnd

;-----------------------------------------------------------------------------
; Datasets
;-----------------------------------------------------------------------------
;
; FileName is the archive without .tar.gz, DirName the directory it unpacks
; to, DataVar the environment variable Geant4 reads.  All three come from
; datasets.tsv; they are not derivable from one another.

!macro DownloadData FileName DirName DataVar
  StrCpy $2 "$TEMP\${FileName}.tar.gz"

  DetailPrint "Downloading ${FileName}.tar.gz"
  inetc::get "https://cern.ch/geant4-data/datasets/${FileName}.tar.gz" $2 /END
  Pop $0
  StrCmp $0 "OK" dl_ok_${DataVar} 0
    DetailPrint "Download failed: $0"
    DetailPrint "Install ${DirName} by hand: fetch ${FileName}.tar.gz from"
    DetailPrint "https://cern.ch/geant4-data/datasets and extract it into"
    DetailPrint "$INSTDIR\${G4_DATA_DIR}"
    Goto done_${DataVar}

  dl_ok_${DataVar}:
    untgz::extract "-d" "$INSTDIR\${G4_DATA_DIR}" $2
    StrCmp $R0 "success" ex_ok_${DataVar} 0
      DetailPrint "Failed to extract $2"
      DetailPrint "Extract it by hand into $INSTDIR\${G4_DATA_DIR}\${DirName}"
      Delete $2
      Goto done_${DataVar}

  ex_ok_${DataVar}:
    Delete $2
    !insertmacro SelectEnvHive
    EnVar::Delete "${DataVar}"
    Pop $0
    EnVar::AddValue "${DataVar}" "$INSTDIR\${G4_DATA_DIR}\${DirName}"
    Pop $0
    DetailPrint "${DataVar} -> $INSTDIR\${G4_DATA_DIR}\${DirName} (EnVar returned |$0|)"

  done_${DataVar}:
!macroend

!include "datasets.nsh"

SectionGroup /e "Data files" SecDat
  !insertmacro G4_DATA_SECTIONS
SectionGroupEnd

;-----------------------------------------------------------------------------

Section -AdditionalIcons
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\Uninstall.lnk" "$INSTDIR\${UNINSTALL_FILENAME}" "/$MultiUser.InstallMode"
SectionEnd

Section -Post
  ; Repair the absolute paths Geant4 and Qt baked in at configure time.  In a
  ; Geant4 11 tree only geant4-config and Geant4Config.cmake normally carry the
  ; prefix, but the geant4make scripts do in some builds, so all are attempted;
  ; _ReplaceInFile on a file that does not contain the string is a no-op.
  ${StrRep} $0 "$INSTDIR" "\" "/"

  ; Geant4Config.cmake also names C:/Qt/6.7.3/msvc2019_64/lib/cmake/Qt6 for
  ; find_dependency(Qt6).  It is left alone: building a Qt application against
  ; the installed Geant4 needs a Qt development install anyway, and the DLLs
  ; in bin have no CMake files to point it at.

  !insertmacro _ReplaceInFile "$INSTDIR\${G4_CMAKE_DIR}\Geant4Config.cmake" \
                              "${G4_BUILD_DIR}" "$0"
  !insertmacro _ReplaceInFile "$INSTDIR\bin\geant4-config" \
                              "${G4_BUILD_DIR}" "$0"
  !insertmacro _ReplaceInFile "$INSTDIR\lib\pkgconfig\G4ptl.pc" \
                              "${G4_BUILD_DIR}" "$0"
  !insertmacro _ReplaceInFile "$INSTDIR\bin\geant4.csh" \
                              "${G4_BUILD_DIR}" "$0"
  !insertmacro _ReplaceInFile "$INSTDIR\bin\geant4.sh" \
                              "${G4_BUILD_DIR}" "$0"
  !insertmacro _ReplaceInFile "$INSTDIR\${G4_SHARE_DIR}\geant4make\geant4make.sh" \
                              "${G4_BUILD_DIR}" "$0"
  !insertmacro _ReplaceInFile "$INSTDIR\${G4_SHARE_DIR}\geant4make\geant4make.csh" \
                              "${G4_BUILD_DIR}" "$0"

  ; Write uninstaller
  WriteUninstaller "$INSTDIR\${UNINSTALL_FILENAME}"

  ; Write the installation path into the registry
  WriteRegStr SHCTX "${MULTIUSER_INST_KEY}" "${MULTIUSER_INSTALLMODE_INSTDIR_REGISTRY_VALUENAME}" "$INSTDIR"

  ; "add/remove programs" will show if installation is per-user or per-machine
  ${if} $MultiUser.InstallMode == "CurrentUser"
	WriteRegStr SHCTX "${MULTIUSER_UNINST_KEY}" "DisplayName" "${MULTIUSER_INSTALLMODE_DISPLAYNAME} (only current user)"
  ${else}
    WriteRegStr SHCTX "${MULTIUSER_UNINST_KEY}" "DisplayName" "${MULTIUSER_INSTALLMODE_DISPLAYNAME}"
  ${endif}

  WriteRegStr SHCTX "${MULTIUSER_UNINST_KEY}" "${MULTIUSER_INSTALLMODE_DEFAULT_REGISTRY_VALUENAME}" \
                    "$\"$INSTDIR\${UNINSTALL_FILENAME}$\" /$MultiUser.InstallMode"

  WriteRegStr SHCTX "${MULTIUSER_UNINST_KEY}" "DisplayVersion" "${APP_VERSION}"
!ifdef G4_HAVE_ICON
  WriteRegStr SHCTX "${MULTIUSER_UNINST_KEY}" "DisplayIcon" "$INSTDIR\share\g4_32.ico"
!else
  WriteRegStr SHCTX "${MULTIUSER_UNINST_KEY}" "DisplayIcon" "$INSTDIR\${UNINSTALL_FILENAME}"
!endif
  WriteRegStr SHCTX "${MULTIUSER_UNINST_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegDWORD SHCTX "${MULTIUSER_UNINST_KEY}" "NoModify" 1
  WriteRegDWORD SHCTX "${MULTIUSER_UNINST_KEY}" "NoRepair" 1
SectionEnd

; Section descriptions
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC01} "Install files for $(^Name), with the Qt 6.7.3 runtime"
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC02} "Install Microsoft's Visual C++ 2015-2022 runtime, which Geant4 and Qt need (skipped when a newer one is there; needs administrator rights)"
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC03} "Add $(^Name) to 'PATH'"
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDat} "Download and unpack the data files. The seven selected by default are the ones Geant4 aborts without; the rest cost about a gigabyte more and are only needed for physics you may never reach."
  !insertmacro G4_DATA_DESCRIPTIONS
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Function .onInit
  !insertmacro MULTIUSER_INIT
FunctionEnd

Function un.onInit
  !insertmacro MULTIUSER_UNINIT
FunctionEnd

Function un.RMDirUP
  !define RMDirUP '!insertmacro RMDirUPCall'

  !macro RMDirUPCall _PATH
    push "${_PATH}"
    Call un.RMDirUP
  !macroend

  ; $0 - current folder
  ClearErrors

  Exch $0
  RMDir "$0\.."

  IfErrors Skip
  ${RMDirUP} "$0\.."
  Skip:

  Pop $0
FunctionEnd

Section "!un.Uninstall files" Uninstall
  Delete "$INSTDIR\${UNINSTALL_FILENAME}"

  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME} Dir.lnk"

  RMDir "$SMPROGRAMS\${APP_NAME}"
  ; Delete recursively all files and folders, the datasets among them
  RMDir /r /REBOOTOK "$INSTDIR"
  ; Delete $INSTDIR's parents (ONLY if they are empty)
  ${RMDirUP} "$INSTDIR"

  ; Remove registry keys
  DeleteRegKey SHCTX "${MULTIUSER_UNINST_KEY}"
  DeleteRegKey SHCTX "${MULTIUSER_INST_KEY}"

  SetAutoClose true

  SectionIn RO
SectionEnd

Section "un.Remove from 'PATH'" UnPath
  !insertmacro SelectEnvHive
  EnVar::DeleteValue "path" "$INSTDIR\bin"
  Pop $0
  DetailPrint "EnVar::DeleteValue returned=|$0|"
SectionEnd

!macro un.DeleteVar DataVar
  !insertmacro SelectEnvHive
  EnVar::Delete ${DataVar}
  Pop $0
  DetailPrint "EnVar::Delete ${DataVar} returned=|$0|"
!macroend

Section "un.Delete data Vars" UnVars
  !insertmacro G4_DATA_UNSETVARS
  !insertmacro un.DeleteVar "QT_PLUGIN_PATH"
SectionEnd

; Section descriptions
!insertmacro MUI_UNFUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${Uninstall} "Uninstall files for $(^Name)"
  !insertmacro MUI_DESCRIPTION_TEXT ${UnPath} "Remove $(^Name) from 'PATH'"
  !insertmacro MUI_DESCRIPTION_TEXT ${UnVars} "Delete the data variables for $(^Name)"
!insertmacro MUI_UNFUNCTION_DESCRIPTION_END
