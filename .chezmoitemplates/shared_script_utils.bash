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


get_json_value_sed() {
    # DESC:
    #         Extract the value for a specified key from a JSON string using sed.
    # ARGS:
    #         $1 (Required) - JSON string to parse
    #         $2 (Required) - Key whose value should be extracted
    # OUTS:
    #         Prints the value associated with the specified key, or an empty string if the key is not found
    # USAGE:
    #         get_json_value_sed '{"foo":"bar"}' "foo"
    local json_string="$1"
    local key="$2"
    # Use sed to find the key, and then extract the value between the quotes
    # This regex looks for "key":" and then captures everything up to the next unescaped quote.
    echo "$json_string" | sed -n "s/.*\"$key\":\"\([^\"]*\)\".*/\1/p"
}