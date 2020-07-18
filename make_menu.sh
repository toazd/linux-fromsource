#!/bin/bash
#Configuration targets:
#  config	  - Update current config utilising a line-oriented program
#  nconfig         - Update current config utilising a ncurses menu based program
#  menuconfig	  - Update current config utilising a menu based program
#  xconfig	  - Update current config utilising a Qt based front-end
#  gconfig	  - Update current config utilising a GTK+ based front-end
#  oldconfig	  - Update current config utilising a provided .config as base
#  localmodconfig  - Update current config disabling modules not loaded
#  localyesconfig  - Update current config converting local mods to core
#  defconfig	  - New config with default from ARCH supplied defconfig
#  savedefconfig   - Save current config as ./defconfig (minimal config)
#  allnoconfig	  - New config where all options are answered with no
#  allyesconfig	  - New config where all options are accepted with yes
#  allmodconfig	  - New config selecting modules when possible
#  alldefconfig    - New config with all symbols set to default
#  randconfig	  - New config with random answer to all options
#  yes2modconfig	  - Change answers from yes to mod if possible
#  mod2yesconfig	  - Change answers from mod to yes if possible
#  listnewconfig   - List new options
#  helpnewconfig   - List new options and help text
#  olddefconfig	  - Same as oldconfig but sets new symbols to their
#                    default value without prompting
#  kvmconfig	  - Enable additional options for kvm guest kernel support
#  xenconfig       - Enable additional options for xen dom0 and guest kernel
#                    support
#  tinyconfig	  - Configure the tiniest possible kernel
#  testconfig	  - Run Kconfig unit tests (requires python3 and pytest)
#
#Cleaning targets:
#  clean		 - Remove most generated files but keep the config and
#                    enough build support to build external modules
#  mrproper	 - Remove all generated files + config + various backup files
#  distclean	 - mrproper + remove editor backup and patch files

function ConfirmToContinue () {
    echo "Are you sure?"
}

function ShowMakeMenu () {
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
                    REPLY=''
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
                    REPLY=''
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
                    REPLY=''
                ;;
                ################################################################
                ("4"|"xconfig"|"qt"|"help 4"|"help xconfig")
                    if [[ $REPLY = @(4|xconfig|qt) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 4"|"help xconfig") ]]; then
                        printf '\n%s\n\n' \
                               "Update current config utilising a Qt based front-end."
                    fi
                    REPLY=''
                ;;
                ################################################################
                ("5"|"gconfig"|"help 5"|"help gconfig")
                    if [[ $REPLY = @(5|gconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 5"|"help gconfig") ]]; then
                        printf '\n%s\n\n' \
                               "Update current config utilising a GTK+ based front-end."
                    fi
                    REPLY=''
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
                    REPLY=''
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
                    REPLY=''
                ;;
                ################################################################
                ("8"|"localmodconfig"|"help 8"|"help localmodconfig")
                    if [[ $REPLY = @(8|localmodconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 8"|"help localmodconfig") ]]; then
                        printf '\n%s\n\n' \
                               "Update current config disabling modules not loaded."
                    fi
                    REPLY=''
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
                    REPLY=''
                ;;
                ################################################################
                ("10"|"savedefconfig"|"help 10"|"help savedefconfig")
                    if [[ $REPLY = @(10|savedefconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 10"|"help savedefconfig") ]]; then
                        printf '\n%s\n\n' \
                               "Save current config as ./defconfig (minimal config)."
                    fi
                    REPLY=''
                ;;
                ################################################################
                ("11"|"diffconfig"|"help 11"|"help diffconfig")
                    if [[ $REPLY = @(11|diffconfig) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 11"|"help diffconfig") ]]; then
                        printf '\n%s\n\n' \
                               "See the changes from .config.old to .config.new"
                    fi
                    REPLY=''
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
                    REPLY=''
                ;;
                ################################################################
                ("13"|"mrproper"|"help 13"|"help mrproper")
                    if [[ $REPLY = @(13|mrproper) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 13"|"help mrproper") ]]; then
                        printf '\n%s\n\n' \
                               "Remove all generated files + config + various backup files."
                    fi
                    REPLY=''
                ;;
                ################################################################
                ("14"|"distclean"|"help 14"|"help distclean")
                    if [[ $REPLY = @(14|distclean) ]]; then
                        echo "$REPLY"
                    elif [[ $REPLY = @("help 14"|"help distclean") ]]; then
                        printf '\n%s\n\n' \
                               "mrproper + remove editor backup and patch files."
                    fi
                    REPLY=''
                ;;
                ################################################################
                ("15"|"done"|"continue")
                    break 2
                ;;
                ################################################################
                ("16"|"quit"|"exit")
                    ConfirmToContinue
                    #continue if not exit
                    REPLY=''
                ;;
                ################################################################
            esac
        done
    done
}

ShowMakeMenu

echo "To the chopper!"
