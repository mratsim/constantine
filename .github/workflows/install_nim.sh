#!/usr/bin/env bash

# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

##########################################
#
#            Nim installer
#        Constantine CI Flavor
#
##########################################

# This script aims to cover all the needs of Constantine CI
# and replaces:
# - Constantine old script in YAML:
#   https://github.com/mratsim/constantine/blob/dc73c71/.github/workflows/ci.yml
# - https://github.com/alaviss/setup-nim
#   which fails in CI for Linux ARM with "cannot execute binary file: Exec format error"
#   unsure why, the same binary works on a Raspberry Pi 4
#
# The official https://github.com/nim-lang/setup-nimble-action
# only deals with nimble.
# and the repo it forked from https://github.com/jiro4989/setup-nim-action
# doesn't support nightly branches only devel
#
# Note: we don't rm temp files in the script to prevent any risk of data loss.
# Those are scary stories:
# - https://github.com/ValveSoftware/steam-for-linux/issues/3671
#   "Moved ~/.local/share/steam. Ran steam. It deleted everything on system owned by user."
# - https://github.com/MrMEEE/bumblebee-Old-and-abbandoned/issues/123
#   "install script does rm -rf /usr for ubuntu"

set -eu
set -o pipefail
shopt -s extglob

# Global variables
# -------------------------
DATE_FORMAT="%Y-%m-%d %H:%M:%S"
_nightlies_url=https://github.com/nim-lang/nightlies/releases

# UI
# -------------------------

info() {
  echo "$(date +"$DATE_FORMAT")" $'\e[1m\e[36m[INF]\e[0m' "$@"
}

ok() {
  echo "$(date +"$DATE_FORMAT")" $'\e[1m\e[32m[ OK]\e[0m' "$@"
}

err() {
  if [[ -n ${GITHUB_ACTION:+z} ]]; then
    echo "::error::" "$@"
  else
    echo "$(date +"$DATE_FORMAT")" $'\e[1m\e[31m[ERR]\e[0m' "$@"
    echo $'\e[1m\e[31mError:\e[0m' "$@" >&2
  fi
}

warn() {
  if [[ -n ${GITHUB_ACTION:+z} ]]; then
    echo "::warning::" "$@"
  else
    echo "$(date +"$DATE_FORMAT")" $'\e[1m\e[33m[WRN]\e[0m' "$@"
    echo $'\e[1m\e[33mWarning:\e[0m' "$@" >&2
  fi
}

# CLI parse
# -------------------------
declare cli_nim_version       # 2.2.0 for release, a branch for nightly or source
declare cli_nim_channel       # release|nightly|source
declare cli_install_dir
declare cli_os
declare cli_arch

while ((0 < $#)); do
  opt="$1"
  case $opt in
    --nim-version) cli_nim_version="$2"; shift 2;;
    --nim-channel) cli_nim_channel="$2"; shift 2;;
    --install-dir) cli_install_dir="$2"; shift 2;;
    --os)   cli_os="$2"; shift 2;;
    --arch) cli_arch="$2"; shift 2;;
    *)
    err "Unknown option '$opt'"
    exit 1
    ;;
  esac
done


# ENV
# -------------------------

fetch_tags() {
  # https://docs.github.com/ja/rest/git/refs?apiVersion=2022-11-28
  curl \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${REPO_GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/repos/nim-lang/nim/git/refs/tags |
    jq -r '.[].ref' |
    sed -E 's:^refs/tags/v::'
}

tag_regexp() {
  version=$1
  echo "$version" |
    sed -E \
      -e 's/\./\\./g' \
      -e 's/^/^/' \
      -e 's/x$//'
}

latest_version() {
  sort -V | tail -n 1
}

function get-version() {
    ## Get the latest released version from 2.x or 2.2.x
    ## Do not modify branch names for nightlies like version-2-2
    local nim_version="$1"
    if [[ "${nim_version}" == "stable" ]]; then
        nim_version=$(curl -sSL https://nim-lang.org/channels/stable)
    elif [[ "$nim_version" =~ ^[0-9]+\.[0-9]+\.x$ ]] || [[ "$nim_version" =~ ^[0-9]+\.x$ ]]; then
        nim_version="$(fetch_tags | grep -E "$(tag_regexp "$nim_version")" | latest_version)"
    fi

    # If using a specific version, but building from source, we need a v prefix
    if [[ "${NIM_CHANNEL}" == "source" ]] && [[ "$nim_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        nim_version="v${nim_version}"
    fi

    echo $nim_version
}

function get-cpu-arch() {
    local ucpu=${1:-$(uname -m)} # `uname -m` Returns arm64 on MacOS and aarch64 on Linux
    local arch
    case "$ucpu" in
        arm64|aarch64)     arch=arm64;;
        arm|armv7l)        arch=arm;;
        x32|i*86)          arch=x32;;
        amd64|x64|x86_64)  arch=x64;;
        *)
        warn "Unknown architecture '$arch'"
        ;;
    esac
    echo $arch
}

function get-os() {
    local uos=${1:-$(uname -s)}
    local os
    case "$uos" in
        linux|Linux*)                    os=Linux;;
        macos|Darwin*)                   os=MacOS;;
        windows|WindowsNT|CYGWIN|MINGW*) os=Windows;;
        FreeBSD*)                        os=FreeBSD;;
        OpenBSD*)                        os=OpenBSD;;
        NetBSD*)                         os=NetBSD;;
        SunOS*)                          os=Solaris;;
        *)
        warn "Unknown OS '$uos'"
        ;;
    esac
    echo $os
}

function get-channel() {
    # Nim releases are prebuilt for Linux and Windows only (x86-64)
    # Nim nightlies are prebuilt for Linux (x86-64 and arm64), Windows x86-64 and MacOS x86-64
    local default=$([[ "$1" =~ ^(Linux|Windows)$ ]] && echo "stable" || echo "source")
    if [[ "$2" != @(|stable|nightly|source) ]]; then
        # Note: @(|stable) means empty OR stable
        err "Invalid channel '$2'. Expected stable, nightly or source."
        exit 1
    fi
    echo "${2:-$default}"
}

CPU_ARCH=$(get-cpu-arch "${cli_arch}")
OS=$(get-os "${cli_os}")
NIM_CHANNEL=$(get-channel "${OS}" "${cli_nim_channel}")
NIM_VERSION=$(get-version "${cli_nim_version:-"stable"}") # Depends on channel to add the `v`
NIM_INSTALL_DIR=${cli_install_dir:="$(pwd)/nim-binaries"}
REPO_GITHUB_TOKEN="" # Placeholder

info "✔ CPU architecture: ${CPU_ARCH}"
info "✔ OS: ${OS}"
info "✔ Nim version: ${NIM_VERSION}"
info "✔ Nim channel: ${NIM_CHANNEL}"
info "✔ Install dir: ${NIM_INSTALL_DIR}"

# Note:
# We can't just move the binaries
# nimble also depends on lib/system.nim due to nimscript

# Building Nim from sources
# -------------------------

function get-hash() {
    ## Get the latest hash of a branch
    ## Unused in this script, but useful as a cache invalidation key
    git ls-remote "https://github.com/$1" "${2:-HEAD}" | cut -f 1
}

function build-nim() {
    builddir="nim-build-${NIM_VERSION}-${OS}-${CPU_ARCH}"

    mkdir -p "${builddir}"
    pushd "${builddir}"
    info "Cloning Nim (${NIM_VERSION})"
    git clone -b "${NIM_VERSION}" --depth 1 https://github.com/nim-lang/Nim
    cd Nim
    info "Building Nim (${NIM_VERSION}) from source."
    ./build_all.sh
    info "Finished building Nim."

    # clean up to save cache space
    rm koch
    rm -rf nimcache
    rm -rf dist
    rm -rf .git

    popd

    cp -a "${builddir}/Nim" "${NIM_INSTALL_DIR}"
    info "Source install finished, binaries are available at \"${NIM_INSTALL_DIR}/bin\""
}

# Download Nim from website
# -------------------------

function download() {
    local url="$1"
    local dest="${2+z}"
    info "Downloading ${url}"
    if [[ -z "${dest}" ]]; then
        # On empty destination reuse the filename
        if ! curl -fsSLO "${url}"; then
            err "Download failure."
            exit 1
        fi
    else
        if ! curl -fsSL "${url}" -o "${dest}"; then
            err "Download failure."
            exit 1
        fi
    fi
    info "Downloaded successfully: ${url}"
}

function download-release() {
    ## Only valid for Windows and Linux, both either 32-bit x86 or x86-64
    local downloaddir="nim-download-${NIM_VERSION}-${OS}-${CPU_ARCH}"

    mkdir -p "${downloaddir}"
    pushd "${downloaddir}"
    case "${OS}" in
        Linux)
            url="https://nim-lang.org/download/nim-${NIM_VERSION}-linux_${CPU_ARCH}.tar.xz"
            download "${url}" nim.zip
            unzip -q nim.zip
            ;;
        Windows)
            url="https://nim-lang.org/download/nim-${NIM_VERSION}_${CPU_ARCH}.zip"
            download "${url}" nim.tar.xz
            tar xJf nim.tar.xz
            ;;
        *)
            err "Invalid OS, prebuilt binaries are not available for '${OS}'"
            exit 1
            ;;
    esac
    popd
    cp -a "${downloaddir}/nim-${NIM_VERSION}" "${NIM_INSTALL_DIR}"
    info "Release install finished, binaries are available at \"${NIM_INSTALL_DIR}/bin\""
}

# Download Nim from nightlies
# ---------------------------

function get-archive-name() {
    local ext=$([[ "${OS}" == Windows ]] && echo ".zip" || echo ".tar.xz")
    local os=$([[ "${OS}" == MacOS ]] && echo "macosx" || echo "$(tr '[:upper:]' '[:lower:]' <<< "${OS}")")
    local arch=$([[ "${CPU_ARCH}" == arm ]] && echo "armv7l" || echo "${CPU_ARCH}")
    echo "${os}_${arch}${ext}"
}

function has-release() {
  local tag=$1
  curl -f -I "${_nightlies_url}/${tag}" >/dev/null 2>&1
}

function extract() {
    local file=$1

    # The nightly builds are stored in a subdir `nim-v2.2.1` or for devel `nim-v2.3.1`
    # We have no easy way to access the version from the name within the nightly repo
    # so we skip it with --strip-components
    # Note that bsdtar might not set executable with the exec flag on unix
    if [[ $file == *.zip ]]; then
        # Windows uses BSD tar: https://github.com/actions/cache/pull/126
        # but it might be overwritten by Git Bash tar!
        # So we use fully qualified path
        /c/Windows/System32/tar.exe -xf "$file" --strip-components=1
    else
        tar -xJf "$file" --strip-components 1
    fi
}

function download-nightly() {
    local downloaddir="nim-download-${NIM_VERSION}-${OS}-${CPU_ARCH}"
    tag=latest-${NIM_VERSION}

    mkdir -p "${downloaddir}"
    pushd "${downloaddir}"
    if has-release "${tag}"; then
        archive=$(get-archive-name)
        local url="${_nightlies_url}/download/${tag}/${archive}"

        download "${url}"
        extract "${archive}"
    else
        err "No nightly release named '$tag'. The provided branch (${NIM_VERSION}) might not be tracked by nightlies, or is being updated."
    fi
    popd
    cp -a "${downloaddir}" "${NIM_INSTALL_DIR}"
    info "Nightly install finished, binaries are available at \"${NIM_INSTALL_DIR}/bin\""
}

# Main
# ---------------------------

case ${NIM_CHANNEL} in
    source) build-nim;;
    nightly) download-nightly;;
    release) download-release;;
    *)
        err "Invalid channel '$2'. Expected stable, nightly or source."
        exit 1
        ;;
esac

ok "Successfully installed Nim."
exit 0
