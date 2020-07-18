#!/usr/bin/env bash

declare -r sSCRIPTVER='0.4.5'

################################################################################
# Msg i(nfo)|s(uccess)|w(arning)|e(rror) "display text" 0/NULL(nosound)|1(sound)
# Standardize the script output to more easily differentiate it from command
# output and enable logging to file a concise summary
# TODO: refactor so type isn't required and no type=info?

function Msg () {

    if [[ $# -lt 2 || $# -gt 3 || ${2:0:1} = " " ]]; then return 1; fi

    local sTYPE="${1:-"error"}" \
          sMSG="${2:-"error"}" \
          iUSESOUND="${3:-"0"}" \
          sTYPENAME=''

    case "${sTYPE,,}" in
        ("i") # Info
            sTYPENAME="INFO"
            echo "==> ${sMSG}"
        ;;
        ("s") # Success
            sTYPENAME="SUCCESS"
            echo -e "${cBGREEN}==> ${sMSG}${cOFF}"
            if (( iUSESOUND )) && (( iSNDTOGGLE )); then PlaySnd "$sTYPE"; fi
        ;;
        ("w") # Warning
            sTYPENAME="WARNING"
            echo -e "${cBYELLOW}==> ${sMSG}${cOFF}"
            if (( iUSESOUND )) && (( iSNDTOGGLE )); then PlaySnd "$sTYPE"; fi
        ;;
        ("e") # Error
            sTYPENAME="ERROR"
            echo -e "${cBRED}==> ${sMSG}${cOFF}"
            if (( iUSESOUND )) && (( iSNDTOGGLE )); then PlaySnd "$sTYPE"; fi
        ;;
        ("*") # Usage error
            echo "Msg function usage error" &>2
            return 1
        ;;
    esac

    # log Msg to file only if the file exists and we have write access to it
    if [[ -f $sLOGFULLNAME && -w $sLOGFULLNAME ]]; then
        printf '%s\n' "$(date "+%m%d%y  %H:%M:%S")  ${sTYPENAME}  ${sMSG}" >> "$sLOGFULLNAME" # double-space delimited
    fi

    return 0
}

function ShowHelp () {
    cat <<- EOHD
${0#*./} v$sSCRIPTVER
    Usage:  ${0#*./} [OPTIONS] [KERNEL.tar.xz]
EOHD
}

################################################################################
# ParseOptions
# parse command line parameters

function ParseOptions () {

    # Initialize all the option variables.
    # This ensures we are not contaminated by variables from the environment.
    file=
    verbose=0

    while :; do
        case $1 in
            -h|-\?|--help)
                ShowHelp
                exit
            ;;
            ${1##*.}=xz)
                echo "$1"
                [[ -f $1 && -r $1 ]] || echo "file not"
                break
            ;;
            --)
                shift
                break
            ;;
            -?*)
                Msg w "Unknown option (ignored): $1"
            ;;
            *)               # Default case: No more options, so break out of the loop.
                ShowHelp
                break
            ;;
        esac
        shift
        done

        return 0
}

ParseOptions "$@"
