#!/usr/bin/env bash
#
#  Author: Hari Sekhon
#  Date: 2008-01-08 13:49:05 +0000 (Tue, 08 Jan 2008)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# Consts and Functions to use when writing Nagios Event Handlers in Bash

# ============================================================================ #
#                V A R I A B L E S   &   C O N S T A N T S                     #
# ============================================================================ #

# Standard Nagios exit codes
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

#MAILTO=${MAILTO:-ops-team@mydomain.com}
LOGFILE=${LOGFILE:-/dev/null}

test_name=""

# Shortcut functions for convenience.
# Override the test_name above to customize
OK(){
    message="${@:-Service OK}"
    [ -n "${test_name:-}" ] && test_name="${test_name%% } "
    echo "${test_name}OK: $message"
    exit $OK
}

WARNING(){
    message="${@:-Service in Warning State}"
    [ -n "${test_name:-}" ] && test_name="${test_name%% } "
    echo "${test_name}WARNING: $message"
    exit $WARNING
}

CRITICAL(){
    message="${@:-Service in Critical State}"
    [ -n "${test_name:-}" ] && test_name="${test_name%% } "
    echo "${test_name}CRITICAL: $message"
    exit $CRITICAL
}

UNKNOWN(){
    message="${@:-Service in Unknown State}"
    [ -n "${test_name:-}" ] && test_name="${test_name%% } "
    echo "${test_name}UNKNOWN: $message"
    exit $UNKNOWN
}

# ============================================================================ #
#           U S A G E   &   A R G   H A N D L I N G   F U N C T I O N S        #
# ============================================================================ #

arg_err(){
    # Takes custom error message to output and then prints usage
    echo "Argument Error: $@"
    echo
    usage || die "NO USAGE HELP AVAILABLE. USAGE NOT DEFINED"
}

usage(){
    # Prints usage for event handler and then calls die to exit. No args.
    echo "GENERIC USAGE ERROR"
    die
}

# ============================================================================ #
#              E R R O R   H A N D L I N G   F U N C T I O N S                 #
# ============================================================================ #

die(){
    # Quits with error message given as argument(s)
    #
    # Usage:
    #
    # die "the problem was X"
    #
    echo "$@"
    exit $CRITICAL
}


# ============================================================================ #
#                      F E A T U R E   F U N C T I O N S                       #
# ============================================================================ #

resolve_name(){
    # Takes One Argument. Determines if arg is a hostname or ip address.
    # If ip address, attempts to resolve it. Returns hostname or UNKNOWN.
    local target="$1"
    [ -n "$target" ] || { echo "no target given" >&2 ; exit 1; }
    #if ! [[ "$name" == [0-9]*.[0-9]*.[0-9]*.[0-9]* ]]; then
    # TODO Improve this Regex
    if grep -E "([12]?[0-9]{1,2}\.){3}[12]?[0-9]{1,2}" <<< "$target" &>/dev/null; then
        if ! type -P host &>/dev/null; then
            echo "Host command not found, unable to resolve ip to hostname for event handler"
            return 1
        fi
        local name=`host "$target" | awk '{print $5}'`
        local name=${name%%.*}
        if [ -z "$name" ]; then
            echo "failed to resolve $target"
            return 1
        fi
    else
        name="$target"
    fi
    echo "$name"
}

# ============================================================================ #
#             N O T I F I C A T I O N   F U N C T I O N S                      #
# ============================================================================ #

notify(){
    # Sends a message by both email and windows pop up to all pre-defined recipients
    #
    # Usage:
    #
    # notify "X has gone wrong with Y"
    #
    mail_msg "$@"
    #netsend_msg "$@"
}

netsend(){
    # Sends a message on one recipient by windows pop up
    #
    # Usage:
    #
    # netsend hostname "X has gone wrong with Y"
    #
    if ! type -P smbclient >/dev/null 2>&1; then
        echo "ERROR: SMBCLIENT NOT FOUND, CANNOT NET SEND"
        return 1
    fi
    local host="$1"
    local message="${@:2}"
    smbclient -M $host <<< "$message" > /dev/null
    local result=$?
    if [ $result -ne 0 ]; then
        echo "ERROR: FAILED TO NET SEND $host"
        return $result
    fi
}

netsend_msg(){
    # Sends a message to all recipients list in ./netsendworkstations
    #
    # Usage:
    #
    # netsend_msg "X has gone wrong with Y"
    #
    WORKSTATIONS="$(sed 's/#.*//' < $(dirname $0)/netsendworkstations)"
    for workstation in $WORKSTATIONS; do
        netsend $workstation <<< "$LOGFILE" &>/dev/null
    done
}

mail_msg(){
    # Sends an email message using the arguments as the title message
    #
    # Usage:
    #
    # mail_msg "X has gone wrong with Y"
    #
    if ! type -P mail >/dev/null 2>&1; then
        echo "ERROR: MAIL COMMAND NOT FOUND IN PATH"
        return 1
    fi
    mail -s "$@" $MAILTO < $LOGFILE
    local result=$?
    if [ $result -ne 0 ]; then
        echo "ERROR SENDING EMAIL TO $MAILTO"
        echo "exit code of mail was: $result"
        return $result
    fi
}
