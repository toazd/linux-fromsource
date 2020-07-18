#!/usr/bin/env bash
#set -x
################################################################################
#                                                                              #
# Script: linux-fromsource.sh                                                  #
# Author: Toazd                                                                #
# Date:   2020                                                                 #
# Version:                                                                     #
# Unlicense:                                                                   #
#    This is free and unencumbered software released into the public domain.   #
#    For more information, please refer to <http://unlicense.org/>             #
# Purpose:                                                                     #
#    Semi-guided patching and compiling of the linux kernel from source to a   #
#    configured directory containing the installable kernel, modules, headers, #
#    backup .config, and a concise log of the scripts activities               #
# Requirements:                                                                #
#    Bash 3.2+                                                                 #
#    TODO                                                                      #
#                                                                              #
################################################################################
declare -r sSCRIPTVER="0.5.1"
#
# Documentation/references:
#    https://www.kernel.org/doc/html/latest/
#    https://wiki.archlinux.org/index.php/Kernel/Traditional_compilation
#
#    https://git.kernel.org/pub/scm/linux/kernel/git/mricon/korg-helpers.git/tree/get-verified-tarball
#     https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/linux-${VER}.tar.xz
#     https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/linux-${VER}.tar.sign
#     https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/sha256sums.asc
#
# Supported utilities:
#    https://github.com/graysky2/modprobed-db
#
# Latest Arch linux config:
#    https://git.archlinux.org/svntogit/packages.git/plain/trunk/config?h=packages/linux
#
# Patch URLs:
#    https://github.com/graysky2/kernel_gcc_patch
#     5.5+
#        https://raw.githubusercontent.com/graysky2/kernel_gcc_patch/master/enable_additional_cpu_optimizations_for_gcc_v9.1%2B_kernel_v5.5%2B.patch
#     5.7+
#        https://raw.githubusercontent.com/graysky2/kernel_gcc_patch/master/enable_additional_cpu_optimizations_for_gcc_v9.1%2B_kernel_v5.7%2B.patch
#
# TODO:
# If the program does terminal interaction, make it output a short
# notice like this when it starts in an interactive mode:
#  <program>  Copyright (C) <year>  <name of author>
#  This program comes with ABSOLUTELY NO WARRANTY; for details type `show w'.
#  This is free software, and you are welcome to redistribute it
#  under certain conditions; type `show c' for details.

# Debugging related options
# TODO cleanup
trap 'printf "\n\nERR: %s\n" "$LINENO"' ERR
trap 'printf "\n--------------\nExit status: %s\nFlags: %s\nLINENO: %s\n" "$?" "$-" "$LINENO"' EXIT

################################################################################
# Shell options & Shell optional behavior

# errexit (-e) - Exit immediately if a command exits with a non-zero status
# errtrace (-E) - If set, the ERR trap is inherited by shell functions
# nounset (-u) - Treat unset variables as an error when substituting
# noclobber (-C) - If set, disallow existing regular files to be overwritten by redirection of output
# extglob - If set, the extended pattern matching features are enabled
set -eEuC
shopt -s extglob

################################################################################
# Global variable initilization

# shellcheck disable=SC2155
InitializeGlobalVars() {

    declare -g sMAKEFLAGS="-j$(nproc)"                                          # make flags (eg. W=1 -j16)
    declare -ga iaPATCHS=(
        "https://raw.githubusercontent.com/graysky2/kernel_gcc_patch/master/enable_additional_cpu_optimizations_for_gcc_v9.1+_kernel_v5.7+.patch"
    )                                                                           # patchs to auto-download and auto-apply (URL/file must end in .patch!)
    declare -g sWORKPATHPARENT="/tmp"                                           # /work/path (path where package will be extracted and compilation will take place) (~2GiB needed for tmpfs)
    declare -g sWORKPATH="${sWORKPATHPARENT}/$(basename "$0" .sh)"              # /work/path/linux-fromsource (use a consistent name to support resuming)
    declare -g sMODPROBEDB="${HOME:-"/home/$USER"}/.config/modprobed.db"        # default modprobed-db database file location
    declare -g sPKGNAME="$(basename "$1")"                                      # linux-x.x.x.tar.xz
    declare -g sPKGPATH="$(dirname "$(realpath "$1")")"                         # /pkg/path/
    declare -g sPKGFULLNAME="$(realpath "$1")"                                  # /pkg/path/linux-x.x.x.tar.xz
    declare -g sPKGBASENAME="${sPKGNAME%.tar.xz}"                               # linux-x.x.x
    declare -g sKVER=${sPKGBASENAME//'linux-'}                                  # x.x.x
    declare -g sKVERMM="${sKVER%.*}"                                            # x.x
    declare -g sKVERMAJOR="${sKVERMM%.*}"                                       # x
    declare -g sEXTRACTPATH="${sWORKPATH:-'.'}/${sPKGNAME%.tar.xz}"             # /work/path/linux-x.x.x
    declare -g sWORKTAR="$sWORKPATH/${sPKGNAME%.xz}"                            # /work/path/linux-x.x.x.tar
    declare -g sWORKPKG="$sWORKPATH/$sPKGNAME"                                  # /work/path/linux-x.x.x.tar.xz
    declare -g sLOCALVER="${sKVER}"                                             # x.x.x (CONFIG_LOCALVERSION gets appended later if set during config)
    declare -g sINSTALLPATH="${sPKGPATH}/INSTALL-${sLOCALVER}"                  # kernel, headers, modules, System.map, .config, and log are copied here (can change later)
    declare -gi iSNDTOGGLE=1                                                    # set to 0 to disable all sounds
    declare -g sSHAFILE="${sWORKPATH}/v${sKVERMAJOR}.x-sha256sums.asc"          # /work/path/v5.x-sha256sums.asc
    declare -g sSIGFILE="${sWORKPATH}/v${sKVERMAJOR}.x-linux-${sKVER}.tar.sign" # /work/path/v5.x-linux-x.x.x.tar.sign
    declare -g sCDNSHAURL="https://cdn.kernel.org/pub/linux/kernel/v${sKVERMAJOR}.x/sha256sums.asc"
    declare -g sCDNSIGURL="https://cdn.kernel.org/pub/linux/kernel/v${sKVERMAJOR}.x/linux-${sKVER}.tar.sign"
    declare -gi iSND_XDG=1                                                      # 1=libcanberra 0=terminal bell
    declare -g sCFGLOCALVER=""                                                  # updates to CONFIG_LOCALVERSION (if set)
    declare -g cOFF='\033[0m'                                                   # text reset
    declare -g cBRED='\033[1;31m'                                               # bold red
    declare -g cBGREEN='\033[1;32m'                                             # bold green
    declare -g cBYELLOW='\033[1;33m'                                            # bold yellow
    declare -gi iRESUME=0                                                       # resume flag
    declare -g sPATCHSRC=""                                                     # placeholder string
    declare -g sCHOICE=""                                                       # string used for choices
    declare -g sPKGSHA256=""                                                    # string for local package sha256sum
    declare -g sCDNSHA256=""                                                    # string for remote sha256sum entry for package
    declare -gi iKSECSTART=0                                                    # make vmlinux start time [date +%s]
    declare -gi iKSECEND=0                                                      # make vmlinux end time
    declare -gi iKSECTOTAL=0                                                    # make vmlinux total seconds (logged)
    declare -gi iKMSECSTART=0                                                   # make modules start time
    declare -gi iKMSECEND=0                                                     # make modules end time
    declare -gi iKMSECTOTAL=0                                                   # make modules total seconds (logged)
    declare -g sLOGPATH="$sWORKPATH"                                            # log file path (gets copied to INSTALL path)
    declare -g sLOGNAME="${0##*/}"                                              # scriptname.sh
    declare -g sLOGNAME="${sLOGNAME%.*}"                                        # scriptname
    declare -g sLOGUID="$(date +%m%d%y-%H:%M:%S)"                               # "unique" id
    declare -g sLOGFULLNAME="${sLOGPATH}/${sLOGNAME}-${sLOGUID}.log"            # full path & file name

    return 0
}

################################################################################
# ParseOptions
# Parse command line parameters and then set any valid options found

ParseOptions() {

    # WIP - parse_options.sh

    return 0
}

################################################################################
# Basic usage check
# Placeholder until command line parsing and options are implemented

UsageCheck() {

    # do not run as root
    if [[ $UID = "0" || $(id -un) = "root" ]]; then
        printf 'This script will not run as root\n'
        return 1
    fi

    # basic parameter checks
    if [[ ! $# -gt 0 || -z $1 || ! -f $1 || $1 = @("-h"|"-help"|"--help"|"-?") ]]; then
        printf "%s v%s\n\n" "${0##*/}" "$sSCRIPTVER"
        printf "Usage:\t%s %s\n" "${0##*/}" "linux-x.x.x.tar.xz"
        exit 0
    elif [[ -f $1 && -r $1 && $1 = *.tar.xz ]]; then
        # test the xz integrity
        printf "==> Testing the integrity of %s using \"xz -d -t -T0 -v -F xz\"...\n" "$1"
        if xz -d -t -T0 -v -F xz "$1"; then
            printf "==> Integrity test passed\n"
        else
            printf "==> Integrity test failed\n"
            return 1
        fi
    fi

    return 0
}

################################################################################
# RequirementsCheck
# Basic required/optional command/library checks
# (fail early if something crucial is missing)

RequirementsCheck() {

    # TODO library checks
    local -ar iaREQCMD=( "touch" "sha256sum" "xz" "grep" "flex" "nproc" "tar" "ld"
                         "readelf" "strip" "gcc" "make" "bc" "perl" "curl" "kmod"
                         "mkdir" "cp" "rm" "basename" "realpath" "dirname" )
    local -ar iaOPTCMD=( "gpg" "rsync" "modprobed-db" "patch" "gsettings" "canberra-gtk-play" )
    declare -gA aaCMD=()
    local sCMD="" iERR=0

    # check required commands, report all that are missing, hash those that are found
    printf "==> Checking for required external commands...\n"
    for sCMD in "${iaREQCMD[@]}"; do
        if [[ $(type -t -P "$sCMD") = "" ]]; then
            printf "==> Required command not found: %s\n" "$sCMD"
            # set the iERR "flag" to 1 if it is not already 1
            (( iERR )) || iERR=1
        else
            # if command is found, add it to associative array
            if hash "$sCMD" &>/dev/null; then
                aaCMD+=(["$sCMD"]="$(hash -t "$sCMD")")
            fi
        fi
    done

    # if any required commands are not found, exit
    if (( ! iERR )); then
        printf "==> All required commands found\n"
    else
        printf "==> Not all required commands were found\n"
        return 1
    fi

    # check optional commands, report reduced features
    # TODO actually disable support
    printf '==> Checking for optional external commands...\n'
    for sCMD in "${iaOPTCMD[@]}"; do
        if [[ $(type -t -P "$sCMD") = "" ]]; then
            printf "==> %s support disabled\n" "$sCMD"
        else
            printf "==> %s support enabled\n" "$sCMD"
            # if command is found, add it to the [cmd]="cmdPath" associative array
            if hash "$sCMD" &>/dev/null; then
                aaCMD+=(["$sCMD"]="$(hash -t "$sCMD")")
            else
                : # TODO can hash fail if type succeeded?
            fi
        fi
    done

    # check for the existance of a command in aaCMD
    #if [[ ${aaCMD[${CMD}]-"not found"} != "not found" ]]; then
    #    echo "true"
    #else
    #    echo "false"
    #fi

    return 0
}

################################################################################
# Msg i(nfo)|s(uccess)|w(arning)|e(rror) "display text" 0/NULL(nosound)|1(sound)
# Standardize the script output to more easily differentiate it from command
# output and enable logging to file a concise summary
# TODO: refactor so type isn't required a required parameter and NULL type=info?

Msg() {

    if [[ $# -lt 2 || $# -gt 3 ]]; then
        echo "Internal parameter error"
        return 1
    fi

    local sTYPE="${1:-"error"}" sMSG="${2:-"error"}" iUSESOUND="${3:-"0"}" sTYPENAME=""

    case "${sTYPE,,}" in
        ("i") # Info
            sTYPENAME="INFO"
            echo "==> ${sMSG}"
        ;;
        ("s") # Success
            sTYPENAME="SUCCESS"
            echo -e "$cBGREEN==> $sMSG$cOFF"
            if (( iUSESOUND )) && (( iSNDTOGGLE )); then PlaySnd "$sTYPE"; fi
        ;;
        ("w") # Warning
            sTYPENAME="WARNING"
            echo -e "$cBYELLOW==> $sMSG$cOFF"
            if (( iUSESOUND )) && (( iSNDTOGGLE )); then PlaySnd "$sTYPE"; fi
        ;;
        ("e") # Error
            sTYPENAME="ERROR"
            echo -e "$cBRED==> $sMSG$cOFF"
            if (( iUSESOUND )) && (( iSNDTOGGLE )); then PlaySnd "$sTYPE"; fi
        ;;
        ("*") # internal usage error
            echo "Msg: type parameter error: \"$sTYPE\""
            return 1
        ;;
    esac

    # log Msg to file only if the file exists and we have write access to it
    if [[ -f $sLOGFULLNAME && -w $sLOGFULLNAME ]]; then
        printf "%s\n" "$(date "+%m%d%y  %H:%M:%S")  $sTYPENAME  $sMSG" >> "$sLOGFULLNAME" # double-space delimited
    fi

    return 0
}

################################################################################
# CopyFromTo
# Copy a file -> file/directory or directory -> path

CopyFromTo() {

    local sFROM=${1:-"error"} sTO=${2:-"error"}

    [[ $sFROM = "error" || $sTO = "error" ]] && return 1
    if [[ -d $sFROM && -r $sFROM ]]; then
        Msg i "Copying $1 to $2"
        cp -rf --strip-trailing-slashes "$sFROM" "$sTO" || { Msg e "Copy $sFROM to $sTO failed" 1; return 1; }
        Msg s "Copy $sFROM to $sTO succeeded"
    elif [[ -f $sFROM && -r $sFROM ]]; then
        Msg i "Copying $1 to $2"
        cp -f "$sFROM" "$sTO" || { Msg e "Copy $sFROM to $sTO failed" 1; return 1; }
        Msg s "Copy $sFROM to $sTO succeeded"
    else
        Msg e "Copy failed, \"$sFROM\" could not be read" 1
        return 1
    fi

    return 0
}

################################################################################
# ChangeDirectory
# Change the working directory to $1

ChangeDirectory() {

    local sFROM=${PWD:-$(command pwd -P)} sTO=${1:-${PWD:-$(command pwd -P)}}

    if [[ ! $sFROM -ef "$sTO" ]]; then
        Msg i "Changing working directory from $sFROM to $sTO"
        if cd "$sEXTRACTPATH"; then
            Msg s "Change working directory succeeded"
        else
            Msg e "Change working directory from $sFROM to $sTO failed"
            return 1
        fi
    else
        Msg w "Change directory skipped, \"$sFROM\"=\"$sTO\"" # $sFROM = $sTO
    fi

    return 0
}

################################################################################
# ConfirmToContinue
# Generic confirmation to continue or quit for non-fatal errors and reviewing
# external command output
# [yY]|[yY][eE][sS] [nN]|[nN][oO]

# shellcheck disable=2120
ConfirmToContinue() {

    local sPREFIX="==> " sPROMPT=${1:-"Do you want to continue?"} sSUFFIX=" "

    while true; do
        read -i "" -rp "${sPREFIX}${sPROMPT}${sSUFFIX}" sCHOICE
        case ${sCHOICE,,} in
            ("y"|"yes")
                break 1
            ;;
            ("n"|"no")
                exit 0
            ;;
            ("*")
                echo "Please enter (y)es or (n)o"
            ;;
        esac
    done

    return 0
}

################################################################################
# Log file init
# A log file is kept in WORKPATH (until completion, when it is copied to
# INSTALLPATH) that logs the date, time, and message(s) that pass through the
# Msg function (concise summary of events)

InitializeLogFile() {

    # write access to log file path
    [[ ! -w $sLOGPATH ]] && { Msg e "No write access to log file path: $sLOGPATH" 1; return 1; }

    # if somehow a log file exists with the same name, backup the old one
    if [[ -f $sLOGFULLNAME~ ]]; then
        Msg e "Existing backup log file at ${sLOGFULLNAME}~ will be overwritten if you continue without moving it" 1
        ConfirmToContinue
    fi

    if [[ -f $sLOGFULLNAME ]]; then
        Msg e "Backing up existing log file at $sLOGFULLNAME with a conflicting name" 1
        mv -fv "$sLOGFULLNAME" "$sLOGFULLNAME~"
    fi

    # if the log file path does not exist, create it
    if [[ ! -d $sLOGPATH ]]; then
        mkdir -p "$sLOGPATH" || { Msg e "Failed to create log file path at $sLOGPATH" 1; return 1; }
        Msg s "Log file path created at $sLOGPATH"
    fi

    # if the log file does not exist, create it
    # if somehow touch fails we try redirection but that will
    # fail if the file already exists (set -C)
    if [[ ! -f $sLOGFULLNAME ]]; then
        if touch "$sLOGFULLNAME"; then
            Msg s "Created a new log file at $sLOGFULLNAME"
        else
            Msg e "\"touch\" $sLOGFULLNAME failed" 1
            Msg i "Attempting to create $sLOGFULLNAME using redirection"
            if printf "" > "$sLOGFULLNAME"; then
                Msg s "Created a new log file at $sLOGFULLNAME"
            else
                Msg e "Failed to create a log file at $sLOGFULLNAME" 1
                return 1
            fi
        fi
    fi

    return 0
}

################################################################################
# Basic access checks
# Fail early if we don't have read or write access where absolutely needed

BasicAccessCheck() {

    # read access to package
    # required to copy the package to the workpath
    [[ ! -r $sPKGFULLNAME ]] && { Msg e "No read access to package: $sPKGFULLNAME" 1; return 1; }

    # write access to package path (for INSTALL- dir)
    # required if installpath resides in packagepath
    # TODO
    [[ ! -w $sPKGPATH ]] && { Msg e "No write access to package: $sPKGPATH" 1; return 1; }

    # if the installpath is inside the pkgpath (default) we will need write access
    # to its parent to create the installdir write access to parent of workpath
    # note: because this is an early check workpath does not exist yet so don't
    # try [[ -w sWORKPATH ]] because it will fail! TODO update if this changes
    # note: the first test requires bash >= 3.2
    if [[ $sINSTALLPATH =~ $sPKGPATH ]]; then
        [[ ! -w $sWORKPATHPARENT ]] && { Msg e "No write access to create working directory" 1; return 1; }
    else
        :
    fi

    return 0
}

################################################################################
# SoundSetup
# configure libcanberra or terminal bell for sounds
# note: only use event ids from the base package sound-theme-freedesktop
# iSND_XDG= 0(terminal bell)|1(libcanberra/sound-theme-freedesktop sounds [Arch])

SoundSetup() {

    if (( iSNDTOGGLE )); then
        Msg i "Sound enabled. Determining type of sounds to be used"
        if command -v canberra-gtk-play &>/dev/null && command -v gsettings &>/dev/null; then
            # if the schema or key is not found
            gsettings get org.gnome.desktop.sound event-sounds &>/dev/null || iSND_XDG=0
            # if the key = false
            ! gsettings get org.gnome.desktop.sound event-sounds &>/dev/null && iSND_XDG=0
            (( iSND_XDG )) && Msg i "Using canberra-gtk-play for sounds"
        else
            iSND_XDG=0
            Msg i "Using terminal bell for sounds"
        fi
    elif (( ! iSNDTOGGLE )); then
        Msg i "Sounds disabled"
    fi

    return 0
}

################################################################################
# PlaySnd s(uccess)|w(arning)|e(rror)
# play a sound type requested or terminal bell

PlaySnd() {

    [[ $# -ne 1 ]] && { echo "Internal parameter error"; return 1; }

    local sTYPE="${1:-"error"}"

    if (( iSNDTOGGLE )); then
        case "${sTYPE,,}" in
            ("s") # Success sound
                if (( iSND_XDG )); then
                    canberra-gtk-play -V -5.0 -i complete &
                elif (( ! iSND_XDG )); then
                    printf '\a' &
                fi
            ;;
            ("w") # Warning sound
                if (( iSND_XDG )); then
                    canberra-gtk-play -V -5.0 -i service-login &
                elif (( ! iSND_XDG )); then
                    printf '\a' &
                fi
            ;;
            ("e") # Error sound
                if (( iSND_XDG )); then
                    canberra-gtk-play -V -5.0 -i suspend-error &
                else
                    printf '\a' &
                fi
            ;;
            ("*") # internal usage error
                echo "PlaySnd: type parameter error: \"$sTYPE\""
                return 1
            ;;
        esac
    fi

    return 0
}

################################################################################
# WorkPathSetup
# TODO split these into two seperate functions

WorkPathSetup() {

    # if workpath already exists and is not the same as the package path ask about removing it
    if [[ -d $sWORKPATH ]] && [[ ! $sWORKPATH -ef $sPKGPATH ]]; then
        Msg s "Existing work directory found at $sWORKPATH"
        while true; do
            read -rp "==> Do you want to remove it? " sCHOICE
            case ${sCHOICE,,} in
                ("y"|"yes")
                    rm -r "$sWORKPATH" || { Msg e "Remove $sWORKPATH failed" 1; return 1; }
                    Msg s "Remove existing work directory at $sWORKPATH succeeded"
                    break 1
                ;;
                ("n"|"no")
                    Msg s "Existing work directory at $sWORKPATH preserved"
                    break 1
                ;;
                ("*")
                    echo "Please enter (y)es or (n)o"
                ;;
            esac
        done
    fi

    # if the work path doesn't exist, create it
    if [[ ! -d $sWORKPATH ]] && [[ ! $sWORKPATH -ef $sPKGPATH ]]; then
        Msg i "Creating work directory"
        mkdir -pv "$sWORKPATH" || { Msg e "Creating work directory at $sWORKPATH failed" 1; return 1; }
        Msg s "Create work directory at $sWORKPATH succeeded"
    fi

    return 0
}

################################################################################
# CheckExtractionPath
# Check for an existing path where we want to extract the package to
# Are we resuming from a failure/abort?

CheckExtractionPath() {

    if [[ -d $sEXTRACTPATH ]]; then
        Msg w "Package extraction path found at $sEXTRACTPATH" 1
        while true; do
            read -rp "==> Do you want to remove it? " sCHOICE
            case ${sCHOICE,,} in
                ("y"|"yes")
                    if rm -r "$sEXTRACTPATH"; then
                        Msg s "Remove $sEXTRACTPATH succeeded"
                    else
                        Msg e "Remove $sEXTRACTPATH failed!" 1
                        ConfirmToContinue
                    fi
                    break 1
                ;;
                ("n"|"no")
                    Msg i "Extraction path preserved at $sEXTRACTPATH"
                    Msg w "Resume enabled, some steps will be skipped"
                    iRESUME=1
                    break 1
                ;;
                ("*")
                    echo "Please enter (y)es or (n)o"
                ;;
            esac
        done
    fi

    return 0
}

################################################################################
# CopyPackageToWorkPath
# if resume is not enabled and workpath != package path, copy package to workpath

CopyPackageToWorkPath() {

    if (( iRESUME )) && [[ ! $sWORKPATH -ef $sPKGPATH ]]; then
        Msg w "Resume enabled, skipping copy package to work directory"
    elif (( ! iRESUME )) && [[ ! $sWORKPATH -ef $sPKGPATH ]]; then
        CopyFromTo "$sPKGFULLNAME" "$sWORKPATH"
    elif [[ $sWORKPATH -ef $sPKGPATH ]]; then
        Msg i "Package path and work path are the same, skipping copy package to work directory"
    fi

    return 0
}

################################################################################
# WorkPackageChecksum
# if resume is not enabled, download checksum file, check the PGP signature for
# the downloaded checksum file, then compare the checksums using a value extracted
# from the downloaded checksum file

WorkPackageChecksum() {

    if (( iRESUME )); then
        Msg w "Resume enabled, skipping $sSHAFILE download and check"
    else
        Msg i "Begining checksum checks"
        Msg i "Downloading ${sCDNSHAURL}"
        if curl -sL "$sCDNSHAURL" -o "$sSHAFILE"; then
            Msg s "Download of $sSHAFILE succeeded"
            # check pgp of checksum file
            Msg i "Checking PGP signature of $sSHAFILE"
            Msg i "Locating keys for autosigner@kernel.org"
            if gpg --locate-keys autosigner@kernel.org; then
                Msg s "Locate keys succeeded"
                Msg i "Verifying PGP signature of $sSHAFILE"
                if gpg --verify "$sSHAFILE"; then
                    Msg w "Review the results carefully..."
                    ConfirmToContinue
                    Msg i "Checking for \"$sPKGNAME\" in $sSHAFILE"
                    # if one entry is found TODO is more than 1 entry ever possible?
                    if [[ $(grep -F "$sPKGNAME" "$sSHAFILE" -c) = "1" ]]; then
                        Msg s "One entry for \"$sPKGNAME\" found in $sSHAFILE"
                        Msg i "Comparing local and remote checksums"
                        sPKGSHA256=$(sha256sum -b "$sWORKPKG")
                        sPKGSHA256=${sPKGSHA256%% *}
                        sCDNSHA256=$(grep -F "$sPKGNAME" "$sSHAFILE")
                        sCDNSHA256=${sCDNSHA256%% *}
                        # compare
                        if [[ $sPKGSHA256 = "$sCDNSHA256" ]]; then
                            Msg s "Local and remote checksums match"
                        else
                            Msg e "Local and remote checksums do not match" 1
                            Msg w "Local sha256sum : $sPKGSHA256"
                            Msg w "Remote sha256sum: $sCDNSHA256"
                            ConfirmToContinue
                        fi
                    elif [[ $(grep -F "$sPKGNAME" "$sSHAFILE" -c) = "0" ]]; then
                        Msg e "No entries found for \"$sPKGNAME\" in $sSHAFILE"
                        Msg i "Running \"sha256sum -c $sSHAFILE --ignore-missing\" for review"
                        sha256sum -c "$sSHAFILE" --ignore-missing
                        ConfirmToContinue
                    else
                        Msg e "Unknown error occured, perform sha256sum check manually" 1
                        ConfirmToContinue
                    fi
                else
                    Msg e "\"gpg --verify $sSHAFILE\" failed" 1
                    ConfirmToContinue
                fi
            else
                Msg e "Unable to locate keys for autosigner@kernel.org" 1
                ConfirmToContinue
            fi
        else
            Msg e "sha256sums.asc download failed. Perform sha256sum check manually" 1
            ConfirmToContinue
        fi
    fi

    return 0
}

################################################################################
# ExtractWorkPackage
# If resume is not enabled, run an integrity check on workpkg and then extract
# the tar from the xz into the work directory

ExtractWorkPackage() {

    if (( iRESUME )); then
        Msg w "Resume enabled, skipping package extraction"
    else
        if [[ -f $sWORKTAR ]]; then Msg i "$sWORKTAR will be removed and replaced if the integrity test succeeds"; fi
        Msg i "Testing the integrity of $sWORKPKG using \"xz -d -t -T0 -v\""
        xz -d -t -T0 -v "$sWORKPKG" || { Msg e "Integrity test failed" 1; return 1; }
        Msg s "Integrity test of $sWORKPKG succeeded"
        Msg i "Extracting $sWORKPKG using \"xz -d -T0 -k -f -v\"..."
        xz -d -T0 -k -f -v "$sWORKPKG" || { Msg e "Extraction failed" 1; return 1; }
        Msg s "Extraction of $sWORKPKG succeeded"
    fi

    return 0
}

################################################################################
# WorkTarPGPCheck
# if not resuming, download and check pgp signature for the package tar

WorkTarPGPCheck() {

    if (( iRESUME )); then
        Msg w "Resume enabled, skipping package PGP signature check"
    else
        # download and check sig
        Msg i "Downloading ${sCDNSIGURL}"
        if curl -sL "$sCDNSIGURL" -o "$sSIGFILE"; then
            Msg s "Download of $sSIGFILE succeeded"
            Msg i "Locating public keys for torvalds@kernel.org and gregkh@kernel.org"
            if gpg --locate-keys torvalds@kernel.org gregkh@kernel.org; then
                Msg w "NOTICE: This script does not modify public key trust level"
                Msg i "Verifying PGP signature..."
                if gpg --verify "$sSIGFILE" "$sWORKTAR"; then
                    Msg w "Review the results carefully..."
                    ConfirmToContinue
                else
                    Msg e "\"gpg --verify $sSIGFILE\" failed" 1
                    ConfirmToContinue
                fi
            else
                Msg e "\"gpg --locate-keys torvalds@kernel.org gregkh@kernel.org\" failed" 1
                ConfirmToContinue
            fi
        else
            Msg e "Download of $sCDNSIGURL failed" 1
            ConfirmToContinue
        fi
    fi

    return 0
}

################################################################################
# ExtractWorkTar
# if not resuming, extract the tar to the workpath

ExtractWorkTar() {

    if (( iRESUME )); then
        Msg w "Resume enabled, skipping tar extraction"
        # TODO if resuming ask if extract tar and overwrite anyway?
    else
        Msg i "Extracting $sWORKTAR to ${sEXTRACTPATH}..."
        if tar -xf "$sWORKTAR" -C "$sWORKPATH"; then
            Msg s "Extraction of $sWORKTAR succeeded"
        else
            Msg e "Extraction of $sWORKTAR failed"
            return 1
        fi
    fi

    return 0
}

################################################################################
# InitializeKernelSource
# if resume is enabled make clean, if not make mrproper
# TODO if resume, ask what to do
# TODO support more options

InitializeKernelSource() {

    if (( iRESUME )); then
        Msg w "Resume enabled, running \"make clean\" (does not remove .config)"
        if make clean; then
            Msg s "\"make clean\" succeeded"
        else
            Msg e "\"make clean\" failed" 1
            return 1
        fi
    else
        Msg i "Running \"make mrproper\""
        if make mrproper; then
            Msg s "\"make mrproper\" succeeded"
        else
            Msg e "\"make mrproper\" failed" 1
            return 1
        fi
    fi

    return 0
}

################################################################################
# ShowMakeMenu
# menu for configure options

ShowMakeMenu() {
    # TODO
    PS3="==> Choose an option by name or number (or help #|name): "
    # TODO not local
    local sOPTIONS=("(make) config" "menuconfig" "nconfig" "xconfig" "gconfig"\
                    "oldconfig" "olddefconfig" "localmodconfig" "defconfig" "savedefconfig"\
                    "diffconfig .config.old .config.new"\
                    "clean" "mrproper" "distclean"\
                    "Continue/done (compile)"\
                    "Quit/exit script")

    while [[ REPLY != @(15|done|continue|16|exit|quit) ]]; do
        printf '\n'
        select sCHOICE in "${sOPTIONS[@]}"; do
            sCHOICE="${REPLY,,}"
            case ${REPLY,,} in
                ################################################################
                ("1"|"config"|"help 1"|"help config")
                    if [[ $REPLY = @(1|config) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 1"|"help config") ]]; then
                        printf '\n%s\n%s\n%s\n%s %s\n\n' \
                               "Update current config utilising a line-oriented program." \
                               "Text based configuration." \
                               "The options are prompted one after another." \
                               "All options need to be answered," \
                               "and out-of-order access to former options is not possible."
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("2"|"menuconfig"|"help 2"|"help menuconfig")
                    if [[ $REPLY = @(2|menuconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 2"|"help menuconfig") ]]; then
                        printf '\n%s\n%s\n%s\n\n' \
                               "Update current config utilising a menu based program." \
                               "An ncurses-based pseudo-graphical menu (only text input)." \
                               "Navigate through the menu to modify the desired options."
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("3"|"nconfig"|"help 3"|"help nconfig")
                    if [[ $REPLY = @(3|nconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 3"|"help nconfig") ]]; then
                        printf '\n%s\n%s\n\n' \
                               "Update current config utilising a ncurses menu based program" \
                               "Pseudo-graphical menu based on ncurses"
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("4"|"xconfig"|"qt"|"help 4"|"help xconfig")
                    if [[ $REPLY = @(4|xconfig|qt) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 4"|"help xconfig") ]]; then
                        printf '\n%s\n\n' \
                               "Update current config utilising a Qt based front-end."
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("5"|"gconfig"|"help 5"|"help gconfig")
                    if [[ $REPLY = @(5|gconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 5"|"help gconfig") ]]; then
                        printf '\n%s\n\n' \
                               "Update current config utilising a GTK+ based front-end."
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("6"|"oldconfig"|"help 6"|"help oldconfig")
                    if [[ $REPLY = @(6|oldconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 6"|"help oldconfig") ]]; then
                        printf '\n%s\n%s\n%s\n\n' \
                               "Update current config utilising a provided .config as base." \
                               "If you copied your .config this allows you to update it with any new kernel options." \
                               "Review changes between kernel versions and update to create a new .config for the kernel."
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("7"|"olddefconfig"|"help 7"|"help olddefconfig")
                    if [[ $REPLY = @(7|olddefconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 7"|"help olddefconfig") ]]; then
                        printf '\n%s\n%s\n%s\n\n' \
                               "Same as oldconfig but sets new symbols to their default value without prompting." \
                               "This is a fast and safe method for upgrading a config file that has all the configuration" \
                               "options it needs for hardware support while at the same time gaining bug fixes and security patches."
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("8"|"localmodconfig"|"help 8"|"help localmodconfig")
                    if [[ $REPLY = @(8|localmodconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 8"|"help localmodconfig") ]]; then
                        printf '\n%s\n\n' \
                               "Update current config disabling modules not loaded."
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("9"|"defconfig"|"help 9"|"help defconfig")
                    if [[ $REPLY = @(9|defconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 9"|"help defconfig") ]]; then
                        printf '\n%s\n%s\n\n' \
                               "New config with default from ARCH supplied defconfig." \
                               "Use this option to get back the default configuration file that came with the sources."
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("10"|"savedefconfig"|"help 10"|"help savedefconfig")
                    if [[ $REPLY = @(10|savedefconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 10"|"help savedefconfig") ]]; then
                        printf '\n%s\n\n' \
                               "Save current config as ./defconfig (minimal config)."
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("11"|"diffconfig"|"help 11"|"help diffconfig")
                    if [[ $REPLY = @(11|diffconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 11"|"help diffconfig") ]]; then
                        printf '\n%s\n\n' \
                               "See the changes from .config.old to .config.new"
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("12"|"clean"|"help 12"|"help clean")
                    if [[ $REPLY = @(12|clean) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 12"|"help clean") ]]; then
                        printf '\n%s %s\n\n' \
                               "Remove most generated files but keep the config and" \
                               "enough build support to build external modules."
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("13"|"mrproper"|"help 13"|"help mrproper")
                    if [[ $REPLY = @(13|mrproper) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 13"|"help mrproper") ]]; then
                        printf '\n%s\n\n' \
                               "Remove all generated files + config + various backup files."
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("14"|"distclean"|"help 14"|"help distclean")
                    if [[ $REPLY = @(14|distclean) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 14"|"help distclean") ]]; then
                        printf '\n%s\n\n' \
                               "mrproper + remove editor backup and patch files."
                    fi
                    REPLY=""
                ;;
                ################################################################
                ("15"|"done"|"continue")
                    break 2
                ;;
                ################################################################
                ("16"|"quit"|"exit")
                    ConfirmToContinue
                    #continue if not exit
                    REPLY=""
                ;;
                ################################################################
            esac
        done
    done

    return 0
}

################################################################################
# TempMakeNConfig
# TODO: make *config (choices)
# config review

TempMakeNConfig() {

    # menu goes here

    Msg i "Running \"make nconfig\" so you can review the config"
    if make nconfig; then
        Msg s "\"make nconfig\" succceeded"
    else
        Msg e "\"make nconfig\" failed" 1
        ConfirmToContinue
    fi

    return 0
}

################################################################################
# Main

Main() {
    # functions that do not depend on the global vars
    UsageCheck "$@"
    ParseOptions # not implemented yet
    RequirementsCheck "$@"
    InitializeGlobalVars "$@"
    # functions that depend on global vars
    WorkPathSetup
    InitializeLogFile
    BasicAccessCheck
    SoundSetup
    CheckExtractionPath
    CopyPackageToWorkPath
    WorkPackageChecksum
    ExtractWorkPackage
    WorkTarPGPCheck
    ExtractWorkTar
    ChangeDirectory "$sEXTRACTPATH"
    InitializeKernelSource
}

################################################################################
#

Main "$@"

#iaPATCHS=()
# if resume is not enabled, download and apply configured patches
# TODO better file type support
if [[ -n ${iaPATCHS[*]} && ${#iaPATCHS[@]} -ge 1 ]]; then
    for sPATCHSRC in "${iaPATCHS[@]}"; do
        [[ $sPATCHSRC == *.patch ]] || continue
        Msg i "Downloading $sPATCHSRC"
        if curl -sL "$sPATCHSRC" -o "${sEXTRACTPATH}/${sPATCHSRC##*/}"; then
            Msg i "Applying patch ${sPATCHSRC##*/}..."
            if patch -Np1 < "${sEXTRACTPATH}/${sPATCHSRC##*/}"; then
                Msg s "Applying ${sPATCHSRC##*/} succeeded"
            else
                if (( iRESUME )); then
                    Msg w "Patch(s) may have already been applied"
                    Msg w "Review the results carefully..."
                    ConfirmToContinue
                else
                    Msg e "Applying ${sEXTRACTPATH}/${sPATCHSRC##*/} failed" 1
                    ConfirmToContinue
                fi
            fi
        else
            Msg e "Download of $sPATCHSRC failed" 1
            ConfirmToContinue
        fi
    done
else
    Msg w "No patchs configured or recognized"
    ConfirmToContinue
fi

# pause for .config import, custom edits, or manual patchs
Msg w "If you want to import a custom config, edit init/Kconfig, or manually add patches now is the time..."
Msg i "Place your custom .config file into $sEXTRACTPATH"
Msg i "Place any *.patch you want auto-applied into $sEXTRACTPATH (or apply them manually using patch)"
Msg i "The latest Arch linux default kernel config can be found at:"
Msg i "https://git.archlinux.org/svntogit/packages.git/plain/trunk/config?h=packages/linux"
# (eg. init/Kconfig - Remove \"depends on ARC\" to enable -O3"
ConfirmToContinue

# if a .config is found at this point it was manually put there
[[ -f "${sEXTRACTPATH}/.config" ]] && Msg s "Imported config found at ${sEXTRACTPATH}/.config"

# if there is no .config and modprobed-db is found run modprobed-db store and then run make localmodconfig
# TODO more make *config options
if [[ ! -f $sEXTRACTPATH/.config ]] && command -v modprobed-db &>/dev/null; then
    # TODO auto support custom modprobed-db db locations ($XDG_CONFIG_HOME/modprobed-db.conf)
    Msg s "modprobed-db found"
    Msg i "Running \"modprobed-db store\""
    if modprobed-db store; then
        Msg s "modprobed-db store succeeded"
        Msg i "Running \"make LSMOD=$sMODPROBEDB localmodconfig\""
        if make LSMOD="$sMODPROBEDB" localmodconfig; then
            Msg s "\"make LSDMOD=$sMODPROBEDB localmodconfig\" succeeded"
        else
            Msg e "\"make LSMOD=$sMODPROBEDB localmodconfig\" failed" 1
            exit 1
        fi
    else
        Msg e "\"modprobed-db store\" failed!" 1
        Msg w "If you continue \"make localmodconfig\" will be run"
        ConfirmToContinue
        if make localmodconfig; then
            Msg s "\"make localmodconfig\" succeeded"
        else
            Msg e "\"make localmodconfig\" failed" 1
            exit 1
        fi
 fi
elif [[ ! -f "${sEXTRACTPATH}/.config" ]]; then
    # no config was imported and modprobe-db is not installed/not found
    Msg w "No .config found, running \"make defconfig\""
    if make defconfig; then
        Msg s "make defconfig succeeded"
    else
        Msg e "make defconfig failed" 1
        exit 1
    fi
fi

# pause for review
ConfirmToContinue

TempMakeNConfig


# TODO last chance edits/checks before make?

# update sLOCALVER and dependant variables with CONFIG_LOCALVERSION
# note: "CONFIG_LOCALVERSION_AUTO is not set"

# confirm the real kernel version (in case the version derived from the file name != the real version)
if [[ $sKVER != "$(make -s kernelversion)" ]]; then
    Msg e "Initial kernel version ($sKVER) is not equal to package actual kernel version ($(make -s kernelversion))" 1
    Msg e "This could indicate a problem with the script or an incorrectly named package"
    ConfirmToContinue
    Msg w "Updating sKVER to the kernel version provided by make"
    sKVER="$(make -s kernelversion)"
else
    Msg i "Kernel version derived from file name matches \"make kernelversion\""
fi

# get the CONFIG_LOCALVERSION line from .config using grep (NULL=not found)
# if "CONFIG_LOCALVERSION is not set", returns NULL
sCFGLOCALVER="$(grep -F "CONFIG_LOCALVERSION=" ".config")"

# strip the text outside the quotes (get the key value)
# CONFIG_LOCALVERSION="example"
if [[ $sCFGLOCALVER != "" ]]; then
    sCFGLOCALVER=${sCFGLOCALVER#*\"}
    sCFGLOCALVER=${sCFGLOCALVER%\"*}
else
    Msg w "CONFIG_LOCALVERSION was not found or is not set"
    Msg s "Default local version ($sLOCALVER) preserved"
fi

# update sLOCALVER and sINSTALLPATH if necessary
# sLOCALVER = x.x.x-CONFIG_LOCALVERSION
# sINSTALLPATH = /pkg/path/INSTALL-x.x.x-CONFIG_LOCALVERSION
if [[ $sCFGLOCALVER != "" && $sCFGLOCALVER != "-" && $sCFGLOCALVER != "_" ]]; then
    Msg s "Updating CONFIG_LOCALVERSION from .config"
    # if sCFGLOCALVER doesn't begin with "-", add it (seperator) if user used "_" as a seperator, let it remain
    if [[ ${sCFGLOCALVER:0:1} != "-" && ${sCFGLOCALVER:0:1} != "_" ]]; then
        sCFGLOCALVER="-${sCFGLOCALVER}"
    fi
    # append [-|_]CONFIG_LOCALVERSION to sLOCALVER
    sLOCALVER="${sKVER}${sCFGLOCALVER}"
    # replace one occurance of sKVER with the new sLOCALVER
    sINSTALLPATH="${sINSTALLPATH/$sKVER/$sLOCALVER}" #sINSTALLPATH="${sPKGPATH}/${sIPPREFIX}-${sLOCALVER}"
    Msg i "Local version updated to $sLOCALVER"
    Msg i "Install path updated to $sINSTALLPATH"
    ConfirmToContinue # TODO remove
else
    Msg w "CONFIG_LOCALVERSION was set to \"$sCFGLOCALVER\""
    Msg s "Default sLOCALVER preserved"
fi

# TODO support config_localversion_auto (scripts/setlocalversion)
if [[ $(grep -F "CONFIG_LOCALVERSION_AUTO=y" ".config") != "" ]]; then
    Msg w "CONFIG_LOCALVERSION_AUTO is not supported by this script"
fi

# create INSTALL subdir in installpath (to hold kernel, modules, and system.map)
# rename any existing backup dirs with a "unique" id
if [[ -d "${sINSTALLPATH}~" ]]; then
    Msg w "Backup install directory already exists"
    # TODO ask if want to remove or rename
    if mv -fv "${sINSTALLPATH}~" "${sINSTALLPATH}~$(date +%s)"; then
        Msg s "Move existing backup directory succeeded"
    else
        Msg e "Move existing backup directory failed" 1
        ConfirmToContinue
    fi
elif [[ -d $sINSTALLPATH ]]; then
    Msg w "Backing up existing install directory"
    if mv -fv "$sINSTALLPATH" "${sINSTALLPATH}~"; then
        Msg s "Backup of existing install directory succeeded"
    else
        Msg e "Backup of existing install directory failed" 1
        ConfirmToContinue
    fi
fi

# if no INSTALL dir or previous was backed up create a new one
if [[ ! -d $sINSTALLPATH ]]; then
    Msg i "Making new install directory at $sINSTALLPATH"
    if mkdir -pv "$sINSTALLPATH"; then
        Msg s "Install directory created at $sINSTALLPATH"
    else
        Msg e "Create install directory at $sINSTALLPATH failed" 1
        exit 1 # TODO return 1
    fi
fi

# backup .config to INSTALL dir
if [[ -f ${sEXTRACTPATH}/.config ]]; then
    CopyFromTo "${sEXTRACTPATH}/.config" "${sINSTALLPATH}/linux-${sLOCALVER}.config"
fi

# make bzImage
Msg i "Running \"make bzImage\""
iKSECSTART=$(date +%s)
if make "$sMAKEFLAGS" bzImage; then
    iKSECEND=$(date +%s)
    iKSECTOTAL=$((iKSECEND - iKSECSTART))
    Msg s "\"make bzImage\" succeeded after ~${iKSECTOTAL} seconds" 1
else
    iKSECEND=$(date +%s)
    iKSECTOTAL=$((iKSECEND - iKSECSTART))
    Msg e "\"make bzImage\" failed after ~${iKSECTOTAL} seconds"
    exit 1 # TODO return 1
fi

# cp bzImage kernel to install dir
# TODO different kernel compile options?
# TODO can the kernel be any other name? (make vmlinux)
# TODO arch/x86_64/boot/bzImage is a sym link to arch/x86/boot/bzImage but is it always?
if [[ ! -f ${sEXTRACTPATH}/arch/x86/boot/bzImage ]]; then
    Msg e "${sEXTRACTPATH}/arch/x86/boot/bzImage not found" 1
    ConfirmToContinue
else
    CopyFromTo "${sEXTRACTPATH}/arch/x86/boot/bzImage" "${sINSTALLPATH}/vmlinuz-${sLOCALVER}"
fi

# copy System.map to install dir
if [[ ! -f ${sEXTRACTPATH}/System.map ]]; then
    Msg e "${sEXTRACTPATH}/System.map not found" 1
    ConfirmToContinue
else
    CopyFromTo "${sEXTRACTPATH}/System.map" "${sINSTALLPATH}/System.map-${sLOCALVER}"
fi

# make modules
Msg i "Running \"make modules\""
iKMSECSTART=$(date +%s)
if make "$sMAKEFLAGS" modules; then
    iKMSECEND=$(date +%s)
    iKMSECTOTAL=$((iKMSECEND - iKMSECSTART))
    Msg s "\"make modules\" succeeded after ~${iKMSECTOTAL} seconds" 1
else
    iKMSECEND=$(date +%s)
    iKMSECTOTAL=$((iKMSECEND - iKMSECSTART))
    Msg e "\"make modules\" failed after ~${iKMSECTOTAL} seconds"
    exit 1 # TODO return 1
fi

# make modules_install to INSTALL dir
Msg i "Running \"make INSTALL_MOD_PATH=${sINSTALLPATH}/modules modules_install\""
if make INSTALL_MOD_PATH="${sINSTALLPATH}/modules" modules_install; then
    Msg s "\"make modules_install\" succceeded"
else
    Msg e "\"make modules_install\" failed"
    ConfirmToContinue
fi

# install kernel headers to install dir
# TODO error/success checking/reporting
if command -v rsync &>/dev/null; then
    Msg i "Installing kernel headers to ${sINSTALLPATH}/"
    make INSTALL_HDR_PATH="${sINSTALLPATH}/kernel_headers/usr/" "$sMAKEFLAGS" headers_install
else
    Msg w "rsync not found, not installing kernel headers"
fi

# Copy log file from workpath to installpath
if [[ -f $sLOGFULLNAME && -r $sLOGFULLNAME ]]; then
    CopyFromTo "$sLOGFULLNAME" "$sINSTALLPATH"
fi

# ask to remove the work dir
# TODO ask if a copy is wanted in INSTALLPATH
if [[ -d $sWORKPATH ]]; then
    Msg s "Work directory is no longer needed"
    while true; do
        read -rp "==> Do you want to remove it? " sCHOICE
        case ${sCHOICE,,} in
            ("y"|"yes")
                rm -r "$sWORKPATH" || { Msg e "Remove $sWORKPATH failed" 1; break 1; }
                Msg s "Remove work directory succeeded"
                break 1
            ;;
            ("n"|"no")
                Msg s "Work directory preserved at $sWORKPATH"
                break 1
            ;;
            (*)
                echo "Please enter (y)es or (n)o"
            ;;
        esac
    done
fi

# TODO
Msg s "Kernel compile complete" 1
Msg s "All completed items were copied to ${sPKGPATH}/INSTALL-${sLOCALVER}"
Msg s "This script does not use sudo or root priveleges so you will need to complete the install manually if desired"
Msg s "Refer to the Arch linux traditional compilation guide (or your distributions' guide) if you need further assistance"
Msg s "    https://wiki.archlinux.org/index.php/Kernel/Traditional_compilation"

#
# mkinitcpio -k ${sLOCALVER} -g /boot/initramfs-${sLOCALVER}.img
# boot config
# /etc/mkinitcpio.d/ preset
#
