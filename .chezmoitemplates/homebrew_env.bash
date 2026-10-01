# Shared preamble for every script that calls brew. chezmoi inherits PATH from
# the shell that launched it, and on a bootstrapping Mac that shell predates
# Homebrew: the prerequisites hook installs it, but the hook is chezmoi's child,
# so the `brew shellenv` it evals never reaches chezmoi or its scripts.
if ! command -v brew &>/dev/null; then
    for prefix in /opt/homebrew /usr/local; do
        if [[ -x ${prefix}/bin/brew ]]; then
            eval "$("${prefix}/bin/brew" shellenv)"
            break
        fi
    done
fi

# Current Homebrew asks "Proceed? [y/n]" before installing dependencies, which
# stalls an unattended apply. Equivalent to passing -y / --no-ask everywhere.
export HOMEBREW_NO_ASK=1
