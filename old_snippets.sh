# if there is no .config and modprobed-db is found run modprobed-db store and then run make localmodconfig
# TODO more make *config options
if [[ ! -f "${sEXTRACTPATH}/.config" ]] && command -v modprobed-db &>/dev/null; then
    # TODO auto support custom modprobed-db db locations ($XDG_CONFIG_HOME/modprobed-db.conf)
    Msg s "modprobed-db found"
    Msg i "Running \"modprobed-db store\""
    if modprobed-db store; then
        Msg s "modprobed-db store succeeded"
        Msg i "Running \"make LSMOD=$sMODPROBEDB localmodconfig\""
        if make LSMOD="$sMODPROBEDB" localmodconfig; then
            Msg s "\"make LSDMOD=$sMODPROBEDB localmodconfig\" succeeded"
        else
            Msg e "\"make LSMOD=$sMODPROBEDB localmodconfig\" failed!" 1
            exit 1
        fi
    else
        Msg e "\"modprobed-db store\" failed!" 1
        Msg w "If you continue \"make localmodconfig\" will be run"
        ConfirmToContinue
        if make localmodconfig; then
            Msg s "\"make localmodconfig\" succeeded"
        else
            Msg e "\"make localmodconfig\" failed!" 1
            exit 1
        fi
 fi
elif [[ ! -f "${sEXTRACTPATH}/.config" ]]; then
    # no config was imported and modprobe-db is not installed/not found
    Msg w "No .config found, running \"make defconfig\""
    if make defconfig; then
        Msg s "make defconfig succeeded"
    else
        Msg e "make defconfig failed!" 1
        exit 1
    fi
fi
























function UsageCheck () {

    if [[ $(id -un) = "root" ]]; then
        printf 'As an extra precaution, this script will not run as root'
        exit 1
    fi

    if [[ ! $# -gt 0 || -z $1 || ! -f $1 ]]; then
        printf '%s - v%s\n\n' "${0##*/}" "$sSCRIPTVER"
        printf 'Example usage:\n'
        printf '\t%s %s\n' "${0##*/}" "${HOME:-"/home/$(id -un)/"}/kernelbuild/linux-x.x.x.tar.xz"
        exit 0
    elif [[ -f $1 && -r $1 && ${1##*.} = "xz" && $1 = *.tar.xz ]]; then
        # test the xz integrity
        printf '==> Testing the integrity of %s using "xz -d -t -T0 -v -F xz"...\n' "$1"
        if xz -d -t -T0 -v -F xz "$1"; then
            printf '==> Integrity test passed\n'
        else
            printf '==> Integrity test failed!\n'
            exit 1
        fi
    fi

    return 0
}

 declare -gi iSND_XDG=1                                                       # 1=libcanberra 0=terminal bell

    if (( iSNDTOGGLE )); then
        if command -v canberra-gtk-play &>/dev/null && command -v gsettings &>/dev/null; then
            # if the schema or key is not found
            gsettings get org.gnome.desktop.sound event-sounds &>/dev/null || iSND_XDG=0
            # if the key = false
            ! gsettings get org.gnome.desktop.sound event-sounds &>/dev/null && iSND_XDG=0
        else
            iSND_XDG=0
        fi
    elif (( ! iSNDTOGGLE )); then
        Msg s "Sounds disabled"
    fi
################################################################################
# PlaySnd s(uccess)|w(arning)|e(rror)
# play a sound type requested or terminal bell

function PlaySnd () {

    [[ $# -ne 1 ]] && return 1 # Usage error

    local sTYPE="${1:-"error"}"

    if (( iSNDTOGGLE )); then
        case "${sTYPE,,}" in
            "s") # Success sound
                if (( iSND_XDG )); then
                    canberra-gtk-play -V -5.0 -i complete &
                elif (( ! iSND_XDG )); then
                    printf '\a' &
                fi
            ;;
            "w") # Warning sound
                if (( iSND_XDG )); then
                    canberra-gtk-play -V -5.0 -i service-login &
                elif (( ! iSND_XDG )); then
                    printf '\a' &
                fi
            ;;
            "e") # Error sound
                if (( iSND_XDG )); then
                    canberra-gtk-play -V -5.0 -i suspend-error &
                else
                    printf '\a' &
                fi
            ;;
            *) # Usage error
                echo "PlaySnd function usage error"
                return 1
            ;;
        esac
    fi

    return 0
}



function CopyPackageToWorkPath () {
  local sPKGSRCSHA='' sPKGCOPYSHA=''

  if (( iRESUME )) && [[ ! $sWORKPATH -ef $sPKGPATH ]]; then
    Msg w "Resume enabled, checking for existing ${sWORKPKG}"
    # if sWORKPKG already exists, make sure it's exactly the same
    if [[ -f $sWORKPKG ]]; then
      Msg s "Existing ${sWORKPKG} found, comparing checksums"
      # get the sha256sum of each file (note: bash will remove the * in binary mode)
      sPKGSRCSHA=$(sha256sum -b "$sPKGFULLNAME")
      sPKGCOPYSHA=$(sha256sum -b "$sWORKPKG")
      # strip away the file name and any spaces
      sPKGSRCSHA=${sPKGSRCSHA%% *}
      sPKGCOPYSHA=${sPKGCOPYSHA%% *}
      if [[ $sPKGSRCSHA = "$sPKGCOPYSHA" ]]; then
        Msg s "Checksums match"
      else
        Msg w "Checksums do not match"
        CopyFromTo "$sPKGFULLNAME" "$sWORKPATH"
      fi
    else
      Msg i "$sWORKPKG not found"
      CopyFromTo "$sPKGFULLNAME" "$sWORKPATH"
    fi
  elif (( ! iRESUME )) && [[ ! $sWORKPATH -ef $sPKGPATH ]]; then
    CopyFromTo "$sPKGFULLNAME" "$sWORKPATH"
  fi

  if [[ $sWORKPATH -ef $sPKGPATH ]]
    Msg s "Package path and work path are the same, copy package to work directory skipped"
  fi
}

sKVER=$(printf '%s' "${sPKGNAME%.tar.xz}" | sed 's/linux-//')    # x.x.x
sPKGPATH=$(dirname "$(realpath "$1")")                           # /pkg/path/
# copy INSTALL dir to PKGPATH
if [[ -d ${sEXTRACTPATH}/INSTALL-${sLOCALVER} ]]; then
  Msg i "Copying INSTALL-${sLOCALVER} to $sPKGPATH"
  # remove existing backup
  if [[ -d $sPKGPATH/INSTALL-${sLOCALVER}~ ]]; then
    Msg w "Removing existing INSTALL backup $sPKGPATH/INSTALL-${sLOCALVER}~ before copying"
    rm -r "$sPKGPATH/INSTALL-${sLOCALVER}~" || { Msg e "Remove failed!" 1; ConfirmToContinue; }
  # create new backup if needed
  elif [[ -d $sPKGPATH/INSTALL-${sLOCALVER} ]]; then
    Msg w "Renaming $sPKGPATH/INSTALL-${sLOCALVER} before copying"
    mv -f "$sPKGPATH/INSTALL-${sLOCALVER}" "$sPKGPATH/INSTALL-${sLOCALVER}~" || { Msg e "Move failed!" 1; ConfirmToContinue; }
  fi
  # copy
  cp -rf "${sEXTRACTPATH}/INSTALL-${sLOCALVER}" "$sPKGPATH" || { Msg e "Copy failed"; ConfirmToContinue; }
  sync &>/dev/null #TODO probably not needed
  Msg s "Copy succeeded"
  # verify that the copy is exactly the same
  Msg i "Checking the copy..."
  if diff -qr "${sEXTRACTPATH}/INSTALL-${sLOCALVER}" "${sPKGPATH}/INSTALL-${sLOCALVER}" &>/dev/null; then
    Msg s "Copy is exactly the same as the source"
  else
    Msg e "Copy does not match the source!" 1
    #TODO try again?
    ConfirmToContinue
  fi
  sync &>/dev/null #TODO probably not needed
  if [[ -d $sWORKPATH ]]; then
    Msg w "Work directory is no longer needed"
    while true; do
      read -rp "==> Do you want to remove it? " sCHOICE
      case ${sCHOICE,,} in
          ("y"|"yes")
            rm -r "$sWORKPATH" || { Msg e "Remove failed!" 1; exit 1; }
            Msg s "Remove work directory succeeded"; break 1
          ;;
          ("n"|"no")
            Msg s "Work directory preserved at $sWORKPATH"; break 1
          ;;
          (*) echo "Please enter (y)es or (n)o" ;;
      esac
    done
  fi
fi
