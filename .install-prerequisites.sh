#!/bin/sh
# Prerequisites that must exist BEFORE chezmoi reads the source state.
#
# Wired up as hooks.read-source-state.pre in .chezmoi.toml.tmpl, so it runs on
# every chezmoi command that reads the source state — including the first
# `chezmoi init --apply` on a bare machine, before any run_ script and before
# any template calling rbwFields is rendered. That is what makes a fresh
# machine converge in one apply instead of two — and, since it also unlocks the
# rbw agent, from a single password prompt rather than one per secret.
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

# This script installs into ~/.local/bin and then calls what it installed, but
# during bootstrap that directory is not yet on PATH — no shell config exists.
# Only affects this process; chezmoi is the parent, which is why the rbw path is
# also pinned in .chezmoi.toml.tmpl.
PATH="${HOME}/.local/bin:${PATH}"
export PATH

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

apt_get() {
    # LC_ALL=C because SSH forwards the client's locale, and on a box that has
    # not generated it yet every apt run buries its output under perl and
    # apt-listchanges warnings. C always exists. `env` rather than a prefix
    # assignment, so the value survives sudo's env_reset either way.
    ${sudo_cmd} env LC_ALL=C LANGUAGE=C DEBIAN_FRONTEND=noninteractive apt-get "$@"
}

install_debian_prerequisites() {
    missing=""
    # pinentry-tty is needed by this script itself, for the rbw unlock below —
    # it cannot wait for the apt package script, which runs later. Same for
    # locales, which ensure_locale needs.
    for package in ca-certificates curl git gnupg locales pinentry-tty unzip; do
        if ! dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q "^install ok installed$"; then
            missing="${missing} ${package}"
        fi
    done

    [ -z "${missing}" ] && return 0

    echo "📦  Installing bootstrap packages:${missing}"
    # shellcheck disable=SC2086
    if ! apt_get update || ! apt_get install -y ${missing}; then
        warn "apt bootstrap failed; later scripts will retry"
        return 1
    fi
}

ensure_locale() {
    # SSH forwards LANG and LC_* from the client, and a Mac sends en_US.UTF-8.
    # Debian generates only C.UTF-8 by default, so every shell the apply spawns
    # warns "setlocale: LC_ALL: cannot change locale (en_US.UTF-8)" — and
    # pinentry loses its LC_CTYPE with it. Generate the locale the client asks
    # for rather than fighting the forwarding.
    if locale -a 2>/dev/null | grep -qix 'en_US\.\(utf8\|utf-8\)'; then
        return 0
    fi

    command -v locale-gen >/dev/null 2>&1 || return 1

    echo "🌐  Generating the en_US.UTF-8 locale"
    if [ -f /etc/locale.gen ] && ! grep -q '^en_US\.UTF-8 UTF-8' /etc/locale.gen; then
        # Uncomment the stock entry, or add one if the file has no such line
        ${sudo_cmd} sed -i 's/^# *en_US\.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
        grep -q '^en_US\.UTF-8 UTF-8' /etc/locale.gen ||
            echo 'en_US.UTF-8 UTF-8' | ${sudo_cmd} tee -a /etc/locale.gen >/dev/null
    fi
    ${sudo_cmd} locale-gen >/dev/null || warn "locale-gen failed; shells will keep warning"
}

install_rbw_darwin() {
    command -v brew >/dev/null 2>&1 || return 1
    echo "🔑  Installing rbw"
    brew install -q rbw || warn "rbw install failed"
}

install_rbw_debian() {
    # rbw is in Debian forky/sid only, so stable boxes take the upstream
    # tarball. Same pin as run_onchange_after_21-rbw, read straight from the
    # data file — this script is not a template, so it cannot interpolate.
    version="$(sed -n 's/^[[:space:]]*rbw:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "${script_dir}/.chezmoidata/packages.yaml" 2>/dev/null)"
    if [ -z "${version}" ]; then
        warn "no rbw pin in .chezmoidata/packages.yaml"
        return 1
    fi

    command -v curl >/dev/null 2>&1 || return 1

    arch="$(dpkg --print-architecture 2>/dev/null)"
    if [ "${arch}" != "amd64" ]; then
        warn "upstream publishes no rbw build for ${arch:-this architecture}; install it manually"
        return 1
    fi

    tmp="$(mktemp -d)" || return 1
    echo "🔑  Installing rbw ${version}"
    # Tarball holds rbw, rbw-agent and completion/ at the top level
    if curl -fsSL --max-time 300 -o "${tmp}/rbw.tar.gz" \
        "https://github.com/doy/rbw/releases/download/${version}/rbw_${version}_linux_amd64.tar.gz" &&
        tar -xzf "${tmp}/rbw.tar.gz" -C "${tmp}"; then
        mkdir -p "${HOME}/.local/bin"
        install -m 0755 "${tmp}/rbw" "${HOME}/.local/bin/rbw"
        install -m 0755 "${tmp}/rbw-agent" "${HOME}/.local/bin/rbw-agent"
    else
        warn "rbw download failed; run_onchange_after_21-rbw will retry"
    fi
    rm -rf "${tmp}"
}

setup_rbw() {
    # rbw keeps the vault key in a background agent, so unlocking here means
    # every rbwFields template in this apply renders from one password prompt.
    command -v rbw >/dev/null 2>&1 || return 1

    email="$(sed -n 's/^[[:space:]]*email[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
        "${config_file}" 2>/dev/null)"
    if [ -n "${email}" ] && ! rbw config show 2>/dev/null | grep -q "\"${email}\""; then
        # Only when it differs: resetting the email invalidates the local db
        echo "🔑  Pointing rbw at ${email}"
        rbw config set email "${email}" || warn "rbw config set email failed"
    fi

    # 24h, so a working day's worth of applies costs one password prompt.
    # rbw's own default is 3600. Seconds.
    if ! rbw config show 2>/dev/null | grep -q '"lock_timeout": 86400'; then
        echo "🔑  Setting rbw lock_timeout to 24h"
        rbw config set lock_timeout 86400 || warn "rbw config set lock_timeout failed"
    fi

    # pinentry-curses needs a usable ncurses geometry, which it does not get when
    # the rbw client is a hook whose stdio chezmoi owns — it dies with "Screen or
    # window too small". pinentry-tty writes straight to the tty rbw passes it via
    # --ttyname, with no layout to get wrong. The Linux boxes here are headless,
    # so there is no GUI pinentry worth preferring.
    if [ "$(uname -s)" = "Linux" ] && command -v pinentry-tty >/dev/null 2>&1 &&
        ! rbw config show 2>/dev/null | grep -q '"pinentry": "pinentry-tty"'; then
        echo "🔑  Setting rbw pinentry to pinentry-tty"
        rbw config set pinentry pinentry-tty || warn "rbw config set pinentry failed"
    fi

    if ! rbw unlocked >/dev/null 2>&1; then
        # unlock fails on a machine that has never logged in; login registers it
        if ! rbw unlock >/dev/null 2>&1 && ! rbw login; then
            warn "could not unlock rbw. Run 'rbw login' in a normal shell, then"
            warn "re-run chezmoi apply — secret-backed files will not render until then."
        fi
    fi
}

case "$(uname -s)" in
    Darwin)
        install_darwin_prerequisites || exit 0
        if [ "${use_secrets}" = true ]; then
            command -v rbw >/dev/null 2>&1 || install_rbw_darwin
            setup_rbw
        fi
        ;;
    Linux)
        # Debian-likes only; ID_LIKE catches Ubuntu, ID=debian catches Proxmox
        if [ -r /etc/os-release ]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            case "${ID:-}:${ID_LIKE:-}" in
                debian:* | *:*debian*)
                    # Twice on purpose. Most images ship the locales package, so
                    # the first call fixes the locale before apt runs and its
                    # output stays clean. On a minimal image locale-gen does not
                    # exist yet, so that call no-ops and the second one — after
                    # apt has installed locales — does the work.
                    ensure_locale
                    install_debian_prerequisites || exit 0
                    ensure_locale
                    ;;
                *)
                    warn "unsupported Linux distribution: ${ID:-unknown}"
                    exit 0
                    ;;
            esac
        fi
        if [ "${use_secrets}" = true ]; then
            command -v rbw >/dev/null 2>&1 || install_rbw_debian
            setup_rbw
        fi
        ;;
    *)
        warn "unsupported OS: $(uname -s)"
        ;;
esac

exit 0
