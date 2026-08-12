#!/bin/sh
# Prerequisites that must exist BEFORE chezmoi reads the source state.
#
# Wired up as hooks.read-source-state.pre in .chezmoi.toml.tmpl, so it runs on
# every chezmoi command that reads the source state — including the first
# `chezmoi init --apply` on a bare machine, before any run_ script and before
# any template calling bitwardenFields is rendered. That is what makes a fresh
# machine converge in one apply instead of two.
#
# The leading dot keeps chezmoi from managing this file as a target.
#
# Two rules for anything added here:
#   1. Exit fast when the tool is already present — this runs constantly.
#   2. Never fail the caller. A non-zero exit blocks every chezmoi command,
#      including the `chezmoi diff` you would use to debug it. Warn instead and
#      let the run_ scripts deal with it.

set -u

warn() { echo "⚠️  install-prerequisites: $*" >&2; }

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# Secret-backed templates only render when use_secrets is on. Read it from the
# generated config rather than `chezmoi data`, which would re-enter this hook.
use_secrets=false
config_file="${XDG_CONFIG_HOME:-${HOME}/.config}/chezmoi/chezmoi.toml"
if [ -f "${config_file}" ] && grep -Eq '^[[:space:]]*use_secrets[[:space:]]*=[[:space:]]*true' "${config_file}"; then
    use_secrets=true
fi

sudo_cmd=""
if [ "$(id -u)" -ne 0 ]; then
    sudo_cmd="sudo"
fi

install_darwin_prerequisites() {
    if ! xcode-select -p >/dev/null 2>&1; then
        echo "🛠   Installing Xcode Command Line Tools"
        xcode-select --install 2>/dev/null || warn "could not trigger the Xcode CLT install"
    fi

    if ! command -v brew >/dev/null 2>&1; then
        if [ -x /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -x /usr/local/bin/brew ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        else
            echo "🍺  Installing Homebrew"
            if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
                warn "Homebrew install failed; package scripts will be skipped"
                return 1
            fi
            [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
        fi

        if [ -x /opt/homebrew/bin/brew ] && ! grep -q 'brew shellenv' "${HOME}/.zprofile" 2>/dev/null; then
            echo "Adding Homebrew to your PATH"
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >>"${HOME}/.zprofile"
        fi
    fi
}

install_debian_prerequisites() {
    missing=""
    for package in ca-certificates curl git gnupg unzip; do
        if ! dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q "^install ok installed$"; then
            missing="${missing} ${package}"
        fi
    done

    [ -z "${missing}" ] && return 0

    echo "📦  Installing bootstrap packages:${missing}"
    # shellcheck disable=SC2086
    if ! DEBIAN_FRONTEND=noninteractive ${sudo_cmd} apt-get update ||
        ! DEBIAN_FRONTEND=noninteractive ${sudo_cmd} apt-get install -y ${missing}; then
        warn "apt bootstrap failed; later scripts will retry"
        return 1
    fi
}

install_bitwarden_cli_darwin() {
    command -v brew >/dev/null 2>&1 || return 1
    echo "🔑  Installing Bitwarden CLI"
    brew install -q bitwarden-cli || warn "bitwarden-cli install failed"
}

install_bitwarden_cli_debian() {
    # No Debian package. Use the same pin as run_onchange_after_21, read straight
    # from the data file — this script is not a template, so it cannot interpolate.
    version="$(sed -n 's/^[[:space:]]*bitwarden_cli:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "${script_dir}/.chezmoidata/packages.yaml" 2>/dev/null)"
    if [ -z "${version}" ]; then
        warn "no bitwarden_cli pin in .chezmoidata/packages.yaml"
        return 1
    fi

    command -v curl >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 || return 1

    case "$(dpkg --print-architecture 2>/dev/null)" in
        amd64) asset="bw-linux-${version}.zip" ;;
        arm64) asset="bw-linux-arm64-${version}.zip" ;;
        *)
            warn "no Bitwarden CLI release for this architecture"
            return 1
            ;;
    esac

    tmp="$(mktemp -d)" || return 1
    echo "🔑  Installing Bitwarden CLI ${version}"
    if curl -fsSL --max-time 300 -o "${tmp}/bw.zip" \
        "https://github.com/bitwarden/clients/releases/download/cli-v${version}/${asset}" &&
        unzip -qo "${tmp}/bw.zip" -d "${tmp}"; then
        mkdir -p "${HOME}/.local/bin"
        install -m 0755 "${tmp}/bw" "${HOME}/.local/bin/bw"
        PATH="${HOME}/.local/bin:${PATH}"
        export PATH
    else
        warn "Bitwarden CLI download failed; run_onchange_after_21 will retry"
    fi
    rm -rf "${tmp}"
}

case "$(uname -s)" in
    Darwin)
        install_darwin_prerequisites || exit 0
        if [ "${use_secrets}" = true ] && ! command -v bw >/dev/null 2>&1; then
            install_bitwarden_cli_darwin
        fi
        ;;
    Linux)
        # Debian-likes only; ID_LIKE catches Ubuntu, ID=debian catches Proxmox
        if [ -r /etc/os-release ]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            case "${ID:-}:${ID_LIKE:-}" in
                debian:* | *:*debian*) install_debian_prerequisites || exit 0 ;;
                *)
                    warn "unsupported Linux distribution: ${ID:-unknown}"
                    exit 0
                    ;;
            esac
        fi
        if [ "${use_secrets}" = true ] && ! command -v bw >/dev/null 2>&1; then
            install_bitwarden_cli_debian
        fi
        ;;
    *)
        warn "unsupported OS: $(uname -s)"
        ;;
esac

exit 0
