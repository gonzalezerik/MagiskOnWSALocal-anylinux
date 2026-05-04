#!/bin/bash
#
# This file is part of MagiskOnWSALocal.
#
# MagiskOnWSALocal is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# MagiskOnWSALocal is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with MagiskOnWSALocal.  If not, see <https://www.gnu.org/licenses/>.
#
# Copyright (C) 2023 LSPosed Contributors
#

if [ ! "$BASH_VERSION" ]; then
    echo "Please do not use sh to run this script, just execute it directly" 1>&2
    exit 1
fi
cd "$(dirname "$0")" || exit 1
abort() {
    [ "$1" ] && echo "ERROR: $1"
    echo "Dependencies: an error has occurred, exit"
    exit 1
}
require_su() {
    if test "$(id -u)" != "0"; then
        if [ "$(sudo id -u)" != "0" ]; then
            echo "sudo is required to run this script"
            abort
        fi
    fi
}

echo "Checking and ensuring dependencies"
check_dependencies() {
    command -v whiptail >/dev/null 2>&1 || command -v dialog >/dev/null 2>&1 || NEED_INSTALL+=("whiptail")
    command -v pip >/dev/null 2>&1 || NEED_INSTALL+=("python3-pip")
    command -v aria2c >/dev/null 2>&1 || NEED_INSTALL+=("aria2")
    command -v 7z >/dev/null 2>&1 || NEED_INSTALL+=("p7zip-full")
    command -v unzip >/dev/null 2>&1 || NEED_INSTALL+=("unzip")
}
check_dependencies

# ---------------------------------------------------------------------------
# Distro detection
#
# We use /etc/os-release (the freedesktop.org standard, present on every
# modern Linux distro) as the primary detection method. The ID and ID_LIKE
# fields tell us which family the distro belongs to. We then fall back to
# legacy release files and finally to scanning $PATH for a known package
# manager binary, so even obscure or unrecognized distros stand a chance
# of working.
# ---------------------------------------------------------------------------
OS_ID=""
OS_ID_LIKE=""
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_ID_LIKE="${ID_LIKE:-}"
fi
# Combine for easier matching below.
OS_FAMILY="$OS_ID $OS_ID_LIKE"

# Map a detected family to the package manager binary we want to use.
PM=""
case " $OS_FAMILY " in
    *" debian "*|*" ubuntu "*)
        PM="apt-get"
        ;;
    *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*|*" ol "*|*" amzn "*|*" openeuler "*)
        # Prefer dnf5 -> dnf -> yum, whichever exists first.
        if command -v dnf5 >/dev/null 2>&1; then
            PM="dnf5"
        elif command -v dnf >/dev/null 2>&1; then
            PM="dnf"
        else
            PM="yum"
        fi
        ;;
    *" arch "*|*" manjaro "*|*" endeavouros "*|*" artix "*|*" garuda "*)
        PM="pacman"
        ;;
    *" suse "*|*" opensuse "*|*" opensuse-tumbleweed "*|*" opensuse-leap "*|*" sles "*)
        PM="zypper"
        ;;
    *" gentoo "*)
        PM="emerge"
        ;;
    *" alpine "*|*" postmarketos "*)
        PM="apk"
        ;;
    *" void "*)
        PM="xbps-install"
        ;;
    *" solus "*)
        PM="eopkg"
        ;;
    *" nixos "*)
        PM="nix-env"
        ;;
esac

# Legacy fallback: if /etc/os-release was missing or didn't tell us anything
# useful, look at the historical release files.
if [ -z "$PM" ]; then
    declare -A legacy_release_files
    legacy_release_files["/etc/redhat-release"]="dnf"
    legacy_release_files["/etc/fedora-release"]="dnf"
    legacy_release_files["/etc/arch-release"]="pacman"
    legacy_release_files["/etc/gentoo-release"]="emerge"
    legacy_release_files["/etc/SuSE-release"]="zypper"
    legacy_release_files["/etc/debian_version"]="apt-get"
    legacy_release_files["/etc/alpine-release"]="apk"
    for f in "${!legacy_release_files[@]}"; do
        if [[ -f $f ]]; then
            PM="${legacy_release_files[$f]}"
            break
        fi
    done
fi

# Final fallback: probe PATH for any package manager we know how to drive.
# This catches niche distros that don't match anything above but still ship
# a recognized package manager binary.
if [ -z "$PM" ]; then
    for candidate in dnf5 dnf yum pacman zypper apt-get apk emerge xbps-install eopkg; do
        if command -v "$candidate" >/dev/null 2>&1; then
            PM="$candidate"
            break
        fi
    done
fi

# If dnf was chosen but dnf5 is also installed, prefer dnf5.
if [ "$PM" = "dnf" ] && command -v dnf5 >/dev/null 2>&1; then
    PM="dnf5"
fi
# yum on a modern Fedora/RHEL is just a dnf shim; prefer real dnf if present.
if [ "$PM" = "yum" ] && command -v dnf >/dev/null 2>&1; then
    PM="dnf"
fi

# ---------------------------------------------------------------------------
# Per-package-manager command tables
# ---------------------------------------------------------------------------
declare -A PM_UPDATE_MAP
PM_UPDATE_MAP["dnf5"]="makecache"
PM_UPDATE_MAP["dnf"]="makecache"
PM_UPDATE_MAP["yum"]="makecache"
PM_UPDATE_MAP["pacman"]="-Syu --noconfirm"
PM_UPDATE_MAP["emerge"]="-auDU1 @world"
PM_UPDATE_MAP["zypper"]="ref"
PM_UPDATE_MAP["apt-get"]="update"
PM_UPDATE_MAP["apk"]="update"
PM_UPDATE_MAP["xbps-install"]="-S"
PM_UPDATE_MAP["eopkg"]="update-repo"
# NOTE: we deliberately use `makecache` instead of `check-update` for the
# RHEL family. `dnf check-update` exits with status 100 when updates are
# available, which the original script would have treated as a failure.
# `makecache` refreshes metadata and exits 0.

declare -A PM_INSTALL_MAP
PM_INSTALL_MAP["dnf5"]="install -y"
PM_INSTALL_MAP["dnf"]="install -y"
PM_INSTALL_MAP["yum"]="install -y"
PM_INSTALL_MAP["pacman"]="-S --noconfirm --needed"
PM_INSTALL_MAP["emerge"]="-a"
PM_INSTALL_MAP["zypper"]="in -y"
PM_INSTALL_MAP["apt-get"]="install -y"
PM_INSTALL_MAP["apk"]="add"
PM_INSTALL_MAP["xbps-install"]="-y"
PM_INSTALL_MAP["eopkg"]="install -y"

declare -A PM_UPGRADE_MAP
PM_UPGRADE_MAP["apt-get"]="upgrade -y"
PM_UPGRADE_MAP["zypper"]="up -y"
PM_UPGRADE_MAP["dnf5"]="upgrade -y"
PM_UPGRADE_MAP["dnf"]="upgrade -y"
PM_UPGRADE_MAP["yum"]="upgrade -y"
PM_UPGRADE_MAP["apk"]="upgrade"
PM_UPGRADE_MAP["xbps-install"]="-Su -y"
PM_UPGRADE_MAP["eopkg"]="upgrade -y"

setup_pm_options() {
    if [ -n "$PM" ]; then
        readarray -td ' ' UPDATE_OPTION <<<"${PM_UPDATE_MAP[$PM]} "
        unset 'UPDATE_OPTION[-1]'
        readarray -td ' ' INSTALL_OPTION <<<"${PM_INSTALL_MAP[$PM]} "
        unset 'INSTALL_OPTION[-1]'
        readarray -td ' ' UPGRADE_OPTION <<<"${PM_UPGRADE_MAP[$PM]} "
        unset 'UPGRADE_OPTION[-1]'
    fi
}

setup_pm_options
require_su
if [ -z "$PM" ]; then
    echo "Unable to determine package manager."
    echo "Detected ID='$OS_ID' ID_LIKE='$OS_ID_LIKE' but no supported"
    echo "package manager (apt-get, dnf, yum, pacman, zypper, apk, emerge,"
    echo "xbps-install, eopkg) was found on PATH. Please install dependencies"
    echo "manually: whiptail (or dialog), python3-pip, aria2, p7zip, unzip."
    abort
elif [[ "$PM" =~ pacman|emerge ]]; then
    [ "$PM" = "emerge" ] && (sudo emerge -qoO aria2[adns] || abort)
    i=30
    while ((i-- > 1)) &&
        ! read -r -sn 1 -t 1 -p $'\r:: Proceed with full system upgrade? Cancel after '$i$'s.. [y/N]\e[0K ' answer; do
        :
    done
    [[ $answer == [yY] ]] && answer=Yes || answer=No
    echo "$answer"
    case "$answer" in
    Yes)
        if ! (sudo "$PM" "${UPDATE_OPTION[@]}" ca-certificates); then abort; fi
        ;;
    *)
        abort "Operation cancelled by user"
        ;;
    esac
else
    # Refresh package metadata, then upgrade ca-certificates so the download
    # steps later in build.sh have a current trust store.
    if ! sudo "$PM" "${UPDATE_OPTION[@]}"; then abort; fi
    if [ -n "${UPGRADE_OPTION[*]}" ]; then
        if ! sudo "$PM" "${UPGRADE_OPTION[@]}" ca-certificates; then abort; fi
    fi
fi

# ---------------------------------------------------------------------------
# Per-package-manager package name translation
#
# The default names in NEED_INSTALL come from Debian. Translate them into the
# native names for whatever package manager we ended up with.
# ---------------------------------------------------------------------------
translate_packages() {
    local -n arr=$1
    local i
    for i in "${!arr[@]}"; do
        case "$PM" in
            apt-get)
                : # Debian names are the canonical form, no change.
                ;;
            dnf5|dnf|yum)
                case "${arr[$i]}" in
                    whiptail)     arr[$i]="newt" ;;
                    p7zip-full)   arr[$i]="p7zip-plugins" ;;
                    python3-pip)  arr[$i]="python3-pip" ;;
                esac
                ;;
            zypper)
                case "${arr[$i]}" in
                    whiptail)     arr[$i]="dialog" ;;
                esac
                ;;
            pacman)
                case "${arr[$i]}" in
                    whiptail)     arr[$i]="libnewt" ;;
                    python3-pip)  arr[$i]="python-pip" ;;
                    p7zip-full)   arr[$i]="p7zip" ;;
                esac
                ;;
            emerge)
                case "${arr[$i]}" in
                    whiptail)     arr[$i]="dialog" ;;
                    python3-pip)  arr[$i]="dev-python/pip" ;;
                    p7zip-full)   arr[$i]="p7zip" ;;
                    aria2)        arr[$i]="net-misc/aria2" ;;
                    unzip)        arr[$i]="app-arch/unzip" ;;
                esac
                ;;
            apk)
                case "${arr[$i]}" in
                    whiptail)     arr[$i]="newt" ;;
                    p7zip-full)   arr[$i]="p7zip" ;;
                esac
                ;;
            xbps-install)
                case "${arr[$i]}" in
                    whiptail)     arr[$i]="dialog" ;;
                    python3-pip)  arr[$i]="python3-pip" ;;
                    p7zip-full)   arr[$i]="p7zip" ;;
                esac
                ;;
            eopkg)
                case "${arr[$i]}" in
                    whiptail)     arr[$i]="newt" ;;
                    python3-pip)  arr[$i]="pip" ;;
                    p7zip-full)   arr[$i]="p7zip" ;;
                esac
                ;;
        esac
    done
}

if [ -n "${NEED_INSTALL[*]}" ]; then
    translate_packages NEED_INSTALL
    if ! (sudo "$PM" "${INSTALL_OPTION[@]}" "${NEED_INSTALL[@]}"); then abort; fi
fi

# ---------------------------------------------------------------------------
# python3-venv handling
#
# Some distros (notably Debian/Ubuntu) ship venv as a separate package; on
# most others it's bundled with the python3 package itself. We only try to
# install something if `import venv` actually fails.
# ---------------------------------------------------------------------------
python_version=$(python3 -c 'import sys;print("{0}{1}".format(*(sys.version_info[:2])))')
PYTHON_VENV_DIR="$(dirname "$PWD")/python3-env"
if [ "$python_version" -ge 311 ] || [ -f "$PYTHON_VENV_DIR/bin/activate" ]; then
    if ! (python3 -c "import venv" >/dev/null 2>&1) || ! (python3 -c "import ensurepip" >/dev/null 2>&1); then
        venv_pkg=""
        case "$PM" in
            zypper)            venv_pkg="python3-venvctrl" ;;
            apt-get)           venv_pkg="python3-venv" ;;
            dnf5|dnf|yum)      : ;; # bundled with python3 on Fedora/RHEL
            pacman)            : ;; # bundled with python on Arch
            apk)               : ;; # bundled with python3 on Alpine
            emerge)            : ;; # bundled with dev-lang/python on Gentoo
            xbps-install)      : ;; # bundled with python3 on Void
            eopkg)             : ;; # bundled with python3 on Solus
        esac
        if [ -n "$venv_pkg" ]; then
            if ! (sudo "$PM" "${INSTALL_OPTION[@]}" "$venv_pkg"); then
                abort
            fi
        fi
    fi
    echo "Creating python3 virtual env"
    python3 -m venv --system-site-packages "$PYTHON_VENV_DIR" || {
        echo "Failed to upgrade python3 virtual env, clear and recreate"
        python3 -m venv --clear --system-site-packages "$PYTHON_VENV_DIR" || abort "Failed to create python3 virtual env"
    }
fi
if [ -f "$PYTHON_VENV_DIR/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$PYTHON_VENV_DIR"/bin/activate || abort "Failed to activate python3 virtual env"
    python3 -c "import pkg_resources; pkg_resources.require(open('requirements.txt',mode='r'))" &>/dev/null || {
        echo "Installing Python3 dependencies"
        python3 -m pip install -r requirements.txt || abort "Failed to install python3 dependencies"
    }
    deactivate
else
    python3 -m pip install -r requirements.txt -q || abort "Failed to install python3 dependencies"
fi
