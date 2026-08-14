#!/bin/sh
# Printed after every `chezmoi apply`, including the apply inside
# `chezmoi init --apply`. Wired to hooks.apply.post in .chezmoi.toml.tmpl.
#
# Registered on apply.post only: init.post also fires during
# `chezmoi init --apply`, so registering both would print this twice.
#
# The leading dot keeps chezmoi from managing this file as a target.
#
# Its job is to close the loop on a bootstrap. A fresh machine finishes an
# apply in a shell that predates everything it just installed: the login shell
# is still whatever it was, ~/.local/bin is not yet on PATH, and none of the
# new tools resolve. That looks like a failed install unless something says
# otherwise.

set -u

printf '\n✅ chezmoi apply complete\n'

todo=""

# $SHELL is the login shell recorded at session start, so it stays stale in the
# session that just switched it — which is exactly the case worth reporting.
# Defaulted because it is not always set, and set -u would abort the hook.
session_shell="${SHELL:-unknown}"
if [ "${session_shell##*/}" != "zsh" ] && command -v zsh >/dev/null 2>&1; then
    todo="${todo}   • This session is running ${session_shell##*/}, not zsh\n"
fi

case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) todo="${todo}   • ~/.local/bin is not on this session's PATH (claude, rbw, herdr live there)\n" ;;
esac

if [ -n "${todo}" ]; then
    printf '\n%b' "${todo}"
    printf '\n   Start a fresh login shell to pick both up:  exec zsh -l\n'
fi

printf '\n'
