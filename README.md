# Geant4 installers

Ready-to-install builds of [Geant4](https://geant4.web.cern.ch/) 11.4.3 with the
Qt6 graphical interface, for Windows, macOS and Linux.

Each installer puts in place the Geant4 libraries, headers, CMake files and
tools, downloads the Geant4 datasets from CERN during the installation, and sets
the environment variables Geant4 needs to find them. When it finishes, Geant4
applications run and new ones can be built against it with CMake.

## Download

Get the file for your system from the
[Releases](https://github.com/ovidiopr/geant4-installers/releases) page:

| System | File |
|---|---|
| Windows 10/11, 64-bit | `Install_Geant4-<version>-<revision>.exe` |
| macOS, Apple silicon | `Install_Geant4-<version>-<revision>.pkg` |
| Ubuntu 24.04 or later, x86-64 | `geant4_<version>-<revision>_amd64.deb` |
| Ubuntu 24.04 or later, ARM64 | `geant4_<version>-<revision>_arm64.deb` |

The installation needs an internet connection: the datasets (about 1.65 GB if
all are selected) are downloaded from CERN, not carried in the installer.

## Datasets

All datasets are selected by default. You can untick any you do not need. The
seven marked as required are the ones Geant4 cannot run without. The others are
only needed by specific physics, for example high-precision neutron transport
(G4NDL, about 1.1 GB on its own) or PIXE (G4PII).

| Dataset | Variable | Contents | Required |
|---|---|---|:-:|
| G4NDL4.7.1 | `G4NEUTRONHPDATA` | Neutron data files, with thermal cross-sections (needed by the _hp physics lists) |  |
| G4EMLOW8.8 | `G4LEDATA` | Data files for low-energy electromagnetic processes | yes |
| PhotonEvaporation6.1.2 | `G4LEVELGAMMADATA` | Data files for photon evaporation | yes |
| RadioactiveDecay6.1.2 | `G4RADIOACTIVEDATA` | Data files for radioactive decay hadronic processes | yes |
| G4PARTICLEXS4.2 | `G4PARTICLEXSDATA` | Evaluated particle cross-sections on natural composition of elements | yes |
| G4PII1.3 | `G4PIIDATA` | Shell ionisation cross-sections (needed for PIXE) |  |
| RealSurface2.2 | `G4REALSURFACEDATA` | Measured optical surface reflectance |  |
| G4SAIDDATA2.0 | `G4SAIDXSDATA` | Evaluated cross-sections from the SAID database |  |
| G4ABLA3.3 | `G4ABLADATA` | Nuclear shell effects in the INCL/ABLA hadronic model | yes |
| G4INCL1.3 | `G4INCLDATA` | Proton and neutron density profiles for INCL | yes |
| G4ENSDFSTATE3.0 | `G4ENSDFSTATEDATA` | Nuclide properties | yes |
| G4CHANNELING2.0 | `G4CHANNELINGDATA` | Crystal channelling data (new in Geant4 11) |  |

## Windows

1. Run `Install_Geant4-<version>-<revision>.exe`. The installer is not signed,
   so Windows SmartScreen may stop it: choose **More info**, then **Run anyway**.
2. Choose whether to install for yourself only or for all users. All users
   needs administrator rights.
3. Choose the components:
   - **Geant4**: the libraries, headers and tools.
   - **Visual C++ runtime**: Microsoft's runtime that Geant4 and Qt need. Leave
     it ticked unless it is already installed.
   - **Add to PATH**: puts the Geant4 `bin` folder on the `PATH` (unticked by
     default).
   - **Datasets**: all ticked; untick the ones you do not want.
4. Choose the installation folder. The default is
   `%LOCALAPPDATA%\Programs\Geant4\Geant4-<version>` for one user, or
   `C:\Program Files\Geant4\Geant4-<version>` for all users.

The installer sets `GEANT4_DATA_DIR`, one variable per installed dataset, and
`QT_PLUGIN_PATH`. A terminal or IDE opened afterwards sees them. Geant4 can be
removed from **Settings > Apps** or with the **Uninstall** shortcut in the Start
menu.

## macOS

1. Open `Install_Geant4-<version>-<revision>.pkg`. The package is not
   notarised, so macOS may refuse to open it: go to **System Settings > Privacy &
   Security** and choose **Open Anyway**, or Control-click the file and choose
   **Open**.
2. Click **Customize** on the *Installation Type* page to choose the datasets
   (all are ticked) and the environment settings.
3. Install. Geant4 goes to `/usr/local/geant4/<version>`.

The installer adds `/usr/local/geant4/<version>/bin` to the `PATH` and sets the
dataset variables for login shells (zsh and bash), and also for applications
started from the Finder or the Dock. Open a new terminal window afterwards.

To remove Geant4, run:

```sh
sudo /usr/local/geant4/<version>/bin/uninstall-geant4.sh
```

## Linux (Ubuntu 24.04 or later)

Install the package with `apt`, which also installs the Qt6, Xerces-C and
OpenGL libraries it depends on:

```sh
sudo apt install ./geant4_<version>-<revision>_amd64.deb
```

During the installation you are asked which datasets to download. All are
selected; press Space to untick one and Enter to continue. To install without
questions, and with every dataset, use

```sh
sudo DEBIAN_FRONTEND=noninteractive apt install ./geant4_<version>-<revision>_amd64.deb
```

Geant4 goes to `/opt/geant4/<version>`. The environment is set in
`/etc/profile.d/geant4.sh`, so log out and back in (or run
`. /etc/profile.d/geant4.sh`) before using it. To remove Geant4, run
`sudo apt remove geant4`. To remove the downloaded datasets as well, run
`sudo apt purge geant4`.

## Adding a dataset later

On macOS and Linux, a dataset left out during installation can be added with
the script installed next to Geant4, for example:

```sh
sudo /opt/geant4/<version>/share/Geant4/fetch-datasets.sh --only G4NDL
```

On macOS, use `/usr/local/geant4/<version>` instead of `/opt/geant4/<version>`.
On Windows, run the installer again and tick the dataset.

## Checking the installation

On macOS and Linux, in a new terminal:

```sh
geant4-config --version
geant4-config --check-datasets
```

On Windows, open a new Command Prompt and run `set G4` to list the dataset
variables. To build an application, point CMake at the installation,
for example `cmake -DGeant4_DIR=/opt/geant4/<version>/lib/cmake/Geant4 ..`.

## Licence

The installer scripts are distributed under the GNU General Public License
v3.0 (see [LICENSE](LICENSE)). Geant4 itself is distributed under the
[Geant4 Software License](https://geant4.web.cern.ch/download/license).
