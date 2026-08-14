# Shared preamble for every script that touches apt: defines SUDO (also used
# for non-apt root work) and apt_get. Pull it in with a template action naming
# this file — spelled out rather than shown literally, because a literal call
# in this comment would recurse until chezmoi hits its template depth limit.

if [[ $(id -u) -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

apt_get() {
    # LC_ALL=C because SSH forwards the client's locale, and on a box that has
    # not generated it every apt run buries its output under perl and
    # apt-listchanges warnings. C always exists. `env` rather than a prefix
    # assignment, so the value survives sudo's env_reset either way.
    ${SUDO} env LC_ALL=C LANGUAGE=C DEBIAN_FRONTEND=noninteractive apt-get "$@"
}
