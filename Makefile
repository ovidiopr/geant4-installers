# Geant4 installers.
#
# Package a Geant4 build with Qt6 so it installs the same way on every platform.
#
# Usage:
#
#   make pkg   GEANT4_SOURCE=/usr/local/geant4/11.4.3 QT_DIR=<Qt>/macos   (macOS)
#   make deb   GEANT4_SOURCE=/opt/geant4/11.4.3            (Linux)
#   make nsis_cmd GEANT4_SOURCE=...                        (prints the command)
#
# GEANT4_SOURCE must be a finished Geant4 installation, i.e. what
# `cmake --install` produced.  It need not have been configured for the
# directory the package installs into: the postinstall rewrites the paths
# Geant4 baked in, which is what the Windows script has always done.
#
# make datasets  regenerates datasets.tsv and the generated NSIS include from
# a Geant4 installation, which is the only step needed after a Geant4 upgrade.

SHELL := /bin/sh

GEANT4_SOURCE ?=
# Qt6 the build was linked against, for macOS: its frameworks go into the tree
QT_DIR        ?=
GEANT4_CONFIG ?= $(if $(GEANT4_SOURCE),$(GEANT4_SOURCE)/bin/geant4-config,$(shell command -v geant4-config))
VERSION       ?= $(shell test -x "$(GEANT4_CONFIG)" && "$(GEANT4_CONFIG)" --version)
REVISION      ?= 1

# Where each platform puts it.  /opt is what Debian policy wants for software
# outside the distribution; /usr/local is the macOS convention.
MACOS_PREFIX  ?= /usr/local/geant4/$(VERSION)
LINUX_PREFIX  ?= /opt/geant4/$(VERSION)

DEB_ARCH      ?= $(shell dpkg --print-architecture 2>/dev/null || echo amd64)

BUILD         ?= build
PKG           ?= $(BUILD)/Install_Geant4-$(VERSION)-$(REVISION).pkg
DEB           ?= $(BUILD)/geant4_$(VERSION)-$(REVISION)_$(DEB_ARCH).deb

.PHONY: all pkg deb nsis_cmd datasets check clean help require_source

help:
	@echo "Geant4 installers"
	@echo
	@echo "  make pkg       GEANT4_SOURCE=<install>   macOS .pkg"
	@echo "  make deb       GEANT4_SOURCE=<install>   Debian .deb"
	@echo "  make nsis_cmd                            the Windows build command"
	@echo "  make datasets  GEANT4_SOURCE=<install>   refresh the dataset table"
	@echo "  make check                               check the scripts and the table"
	@echo
	@echo "  GEANT4_SOURCE = $(GEANT4_SOURCE)"
	@echo "  VERSION       = $(VERSION)"
	@echo "  MACOS_PREFIX  = $(MACOS_PREFIX)"
	@echo "  LINUX_PREFIX  = $(LINUX_PREFIX)"

require_source:
	@test -n "$(GEANT4_SOURCE)" || \
		{ echo "ERROR: set GEANT4_SOURCE to a Geant4 installation"; exit 1; }
	@test -d "$(GEANT4_SOURCE)/lib" || \
		{ echo "ERROR: $(GEANT4_SOURCE) is not a Geant4 installation"; exit 1; }
	@test -n "$(VERSION)" || \
		{ echo "ERROR: could not determine the version; set VERSION"; exit 1; }

pkg: require_source
	@mkdir -p $(BUILD)
	./macos/deploy-qt.sh "$(GEANT4_SOURCE)" "$(QT_DIR)"
	./macos/build-pkg.sh --source "$(GEANT4_SOURCE)" --version "$(VERSION)" \
	    --prefix "$(MACOS_PREFIX)" --output "$(PKG)" --build "$(BUILD)/macos"

deb: require_source
	@mkdir -p $(BUILD)
	./linux/build-deb.sh --source "$(GEANT4_SOURCE)" --version "$(VERSION)" \
	    --revision "$(REVISION)" --prefix "$(LINUX_PREFIX)" --arch "$(DEB_ARCH)" \
	    --output "$(DEB)" --build "$(BUILD)/linux"

# There is no makensis on macOS or Linux worth relying on, and the script needs
# the Geant4 tree laid out beside it, so this prints the command rather than
# pretending to run it.
nsis_cmd:
	@echo "On the Windows machine, with the Geant4 tree one level above:"
	@echo
	@echo "  cd installers\\geant4\\windows"
	@echo "  makensis Geant4.nsi"
	@echo
	@echo "Requires the inetc, untgz and EnVar plugins and the ReplaceInFile"
	@echo "and StrFunc headers, and g4_32.ico, g4_32_un.ico and g4.bmp in the"
	@echo "same directory.  Edit QT_BUILD_DIR and G4_BUILD_DIR at the top of"
	@echo "Geant4.nsi to match the machine the tree was built on."

datasets: require_source
	./update-datasets.sh "$(GEANT4_CONFIG)" > datasets.tsv.new
	@if cmp -s datasets.tsv datasets.tsv.new; then \
		rm -f datasets.tsv.new; echo "datasets.tsv is already current"; \
	else \
		mv datasets.tsv.new datasets.tsv; echo "datasets.tsv updated"; \
	fi
	./windows/gen-datasets-nsh.sh > windows/datasets.nsh
	@echo "windows/datasets.nsh regenerated"
	@echo
	@echo "Check the 'required' column and the descriptions for any dataset"
	@echo "that is new: update-datasets.sh cannot know them and leaves them blank."

# Everything that can be checked without a Geant4 tree, a Debian box or a
# Windows box.  Run it after editing any of the scripts.
check:
	@fail=0; \
	for f in fetch-datasets.sh update-datasets.sh \
	         macos/build-pkg.sh macos/geant4-setenv-launchd.sh \
	         macos/uninstall-geant4.sh.in \
	         macos/scripts/core-postinstall.in \
	         macos/scripts/dataset-postinstall.in \
	         macos/scripts/env-shell-postinstall.in \
	         macos/scripts/env-agent-postinstall.in \
	         linux/build-deb.sh windows/gen-datasets-nsh.sh macos/deploy-qt.sh \
	         linux/debian/config.in linux/debian/postinst.in \
	         linux/debian/prerm.in linux/debian/postrm.in \
	         windows/check-nsi.sh; do \
	    if sh -n "$$f" 2>/dev/null; then echo "  ok      $$f"; \
	    else echo "  SYNTAX  $$f"; fail=1; fi; \
	done; \
	rows=$$(grep -vc '^#' datasets.tsv); \
	cols=$$(awk -F'\t' '!/^#/ && NF != 6 { n++ } END { print n+0 }' datasets.tsv); \
	req=$$(awk -F'\t' '!/^#/ && $$5 == 1' datasets.tsv | wc -l | tr -d ' '); \
	echo "  $$rows datasets, $$req required, $$cols malformed rows"; \
	test "$$cols" = "0" || fail=1; \
	gen=$$(./windows/gen-datasets-nsh.sh | diff -q - windows/datasets.nsh >/dev/null 2>&1 && echo current || echo STALE); \
	echo "  windows/datasets.nsh: $$gen"; \
	test "$$gen" = "current" || fail=1; \
	./windows/check-nsi.sh || fail=1; \
	exit $$fail

all: pkg

clean:
	rm -rf $(BUILD) macos/build linux/build
	rm -f macos/Install_Geant4-*.pkg linux/geant4_*.deb datasets.tsv.new
