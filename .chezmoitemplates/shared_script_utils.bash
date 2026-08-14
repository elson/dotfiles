_inArray_() {
    # DESC:
    #         Determine if a regex matches an array element.  Default is case sensitive.
    #         Pass -i flag to ignore case.
    # ARGS:
    #         $1 (Required) - Value to search for
    #         $2 (Required) - Array written as ${ARRAY[@]}
    # OPTIONS:
    #         -i (Optional) - Ignore case
    #         -r (Optional) - Use regex
    # OUTS:
    #         0 if true
    #         1 if untrue
    # USAGE:
    #         if _inArray_ "VALUE" "${ARRAY[@]}"; then ...
    #         if _inArray_  -i "VALUE" "${ARRAY[@]}"; then ...
    # CREDIT:
    #         https://github.com/labbots/bash-utility

    [[ $# -lt 2 ]] && fatal "Missing required argument to ${FUNCNAME[0]}"

    local _use_regex=false
    local opt
    local OPTIND=1
    while getopts ":iIrR" opt; do
        case ${opt} in
            i | I)
                #shellcheck disable=SC2064
                trap '$(shopt -p nocasematch)' RETURN # reset nocasematch when function exits
                shopt -s nocasematch                  # Use case-insensitive regex
                ;;
            r | R)
                _use_regex=true
                ;;
            *) fatal "Unrecognized option '${1}' passed to ${FUNCNAME[0]}. Exiting." ;;
        esac
    done
    shift $((OPTIND - 1))

    local _array_item
    if ${_use_regex}; then
        local _value="${1}"
    else
        local _value="^${1}$"
    fi
    shift
    for _array_item in "$@"; do
        [[ ${_array_item} =~ ${_value} ]] && return 0
    done
    return 1
}


_debArch_() {
    # DESC:
    #         Print the Debian architecture name for this machine (amd64, arm64, …).
    #         Used by the release-download installers to pick the right asset.
    # OUTS:
    #         Prints the architecture, or exits 1 if dpkg is unavailable
    # USAGE:
    #         arch="$(_debArch_)"
    if ! command -v dpkg &>/dev/null; then
        echo "dpkg not found; cannot determine architecture" >&2
        return 1
    fi
    dpkg --print-architecture
}


_versionStamp_() {
    # DESC:
    #         Path to the stamp file recording which pinned version of a tool is
    #         installed. Lets the release-download installers skip work on a
    #         re-run without parsing `--version`, which not every tool reports
    #         usefully (gron built from source just says "dev").
    # ARGS:
    #         $1 (Required) - Tool name
    # OUTS:
    #         Prints the stamp file path
    # USAGE:
    #         stamp="$(_versionStamp_ gron)"
    #         [[ $(cat "${stamp}" 2>/dev/null) == "${version}" ]] && return 0
    echo "${XDG_STATE_HOME:-${HOME}/.local/state}/dotfiles/versions/${1}"
}
