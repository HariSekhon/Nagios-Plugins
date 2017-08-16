#!/usr/bin/env bash
#
#  Author: Hari Sekhon
#  Date: 2008-01-08 13:00:54 +0000 (Tue, 08 Jan 2008)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# Consts and Functions to use when writing Nagios Event Handlers in Bash

# First things first, let's get all generic Nagios stuff
lib="lib_nagios.sh"
srcdir=`dirname $0`
. "$srcdir"/$lib ||
    {   echo "Error Sourcing Nagios Library"
        mail -s "$HOSTNAME: Event Handler Error Sourcing Nagios Library" ${MAILTO:-ops@mydomain.com} < /dev/null
        exit 3
    }

#
# Now replacement or addition to standard stuff follows
#

# ============================================================================ #
#                V A R I A B L E S   &   C O N S T A N T S                     #
# ============================================================================ #

#srcdir=`dirname $0`
#LOGFILE=${LOGFILE:-/dev/null}

# ============================================================================ #
#              C H A I N E D   S O U R C I N G   F U N C T I O N S             #
# ============================================================================ #

source_nrpe(){
    local lib="lib_check_nrpe.sh"
    . "$srcdir/$lib" ||
        {   echo "Event Handler: FAILED to source $lib properly"
            mail -s "$HOSTNAME: Event Handler Error Sourcing Nrpe" $MAILTO < $LOGFILE
            die
        }
}

source_nt(){
    local lib="lib_check_nt.sh"
    . "$srcdir/$lib" ||
        {   echo "Event Handler: FAILED to source $lib properly"
            mail -s "$HOSTNAME: Event Handler Error Sourcing Check_nt" $MAILTO < $LOGFILE
            die
        }
}

# ============================================================================ #
#           U S A G E   &   A R G   H A N D L I N G   F U N C T I O N S        #
# ============================================================================ #

usage(){
    # Prints usage for event handler and then calls die to exit. No args.
    echo
    echo "Nagios Event Handler"
    echo
    echo "usage: ${0##*/} -H HOSTADDRESS -s SERVICESTATE -t SERVICESTATETYPE -o SERVICEOUTPUT"
    echo
    echo "All arguments are required. They correspond to Nagios Macros"
    echo
    echo "  HOSTADDRESS         The IP Adress or Hostname against which this event handler"
    echo "                      should fire. If you are checking a service through a "
    echo "                      public interface then you should probably be using a"
    echo "                      static internal hostname or ip address, not a Nagios macro"
    echo
    echo "  SERVICESTATE        The State of the service that was checked."
    echo "                      Valid Values: OK, WARNING, CRITICAL, UNKNOWN"
    echo "                      Values are case sensitive"
    echo
    echo "  SERVICESTATETYPE    The State type. Valid values: SOFT, HARD"
    echo "                      Values are case sensitive"
    echo
    echo "  SERVICEOUTPUT       The Output from the service check which should include"
    echo "                      the error message which can be used for logical handling"
    echo
    die
} >&2

parse_args(){
    # Does all the option processing for the 4 main options that you need for an event handler
    #
    # Usage:
    #
    # parse_args $@
    #
    # Useful if you are doing the basic args, if you need something more specific you'll have to roll your own
    # Missing OO here really but it's still faster to develop in this.
    #
    while [ "$#" -ge 1 ]; do
        case "$1" in
            -h|--help)  usage
                        ;;
                   -H)  if ! [ $# -ge 2 ]; then
                            arg_err "You must supply a HOSTNAME/IP ADDRESS after the -H switch"
                        else
                            HOST="$2"
                        fi
                        ;;
                   -s)  if ! [ $# -ge 2 ]; then
                            arg_err "You must supply a SERVICESTATE after the -s switch"
                        else
                            STATE="$2"
                        fi
                        ;;
                   -t)  if ! [ $# -ge 2 ]; then
                            arg_err "You must supply a SERVICESTATETYPE after the -t switch"
                        else
                            STATETYPE="$2"
                        fi
                        ;;
                   -o)  if ! [ $# -ge 2 ]; then
                            arg_err "You must supply SERVICEOUTPUT after the -o switch"
                        else
                            SERVICEOUTPUT="$2"
                        fi
                        ;;
                    *)  arg_err "'$1' is not valid option"
                        ;;
        esac
        shift
        shift
    done
}

validate_input(){
    # Performs checks on the 4 basic options that you need for an event handler
    #
    # Usage:
    #
    # validate_args
    #
    # Should be called after parse_args in event handler
    #
    if [ -z "${HOST:-}" ]; then
        arg_err "You must supply a HOSTNAME/IP ADDRESS"
    elif ! grep "^[A-Za-z0-9\.-]\+$" <<< "$HOST" &>/dev/null; then
        arg_err "'$HOST' is not a valid host name"
    fi

    if [ -z "${STATE:-}" ]; then
        arg_err "You must supply a SERVICESTATE"
    elif [ "$STATE" != "OK"     \
      -a "$STATE" != "WARNING"  \
      -a "$STATE" != "CRITICAL" \
      -a "$STATE" != "UNKNOWN" ]; then
        arg_err "STATE supplied is INVALID - must be one of the following: OK, WARNING, CRITICAL, UNKNOWN"
    fi

    if [ -z "${STATETYPE:-}" ]; then
        arg_err "You must supply a SERVICESTATETYPE (ie HARD or SOFT)"
    elif [ "$STATETYPE" != "HARD" -a "$STATETYPE" != "SOFT" ]; then
        arg_err "STATETYPE supplied is INVALID - must be either HARD or SOFT"
    fi

    if [ -z "${SERVICEOUTPUT:-}" ]; then
        arg_err "You must supply the SERVICEOUTPUT"
    fi
}


# ============================================================================ #
#              E R R O R   H A N D L I N G   F U N C T I O N S                 #
# ============================================================================ #

die(){
    # Quits with message and notifications
    #
    # Usage:
    #
    # die "the problem was X"
    #
    # Takes the initial name of the event handler in order to keep it generic enough
    # to be used everywhere and still retain a custom title for notification
    #
    # Name of caller should be event_XYZ
    # X is then stripped out and used such
    # EMAIL: "$HOSTNAME: XYZ Event Handler Error"
    #
    # Expects MAILTO and LOGFILE to be set, otherwise defaults to ops@mydomain.com
    # and dev null for safety
    echo "$@"
    local MAILTO=${MAILTO:-ops@mydomain.com}
    local LOGFILE=${LOGFILE:-/dev/null}
    if grep "^event_handler_[A-Za-z0-9]\+$" <<< "$0" &>/dev/null; then
        local event_handler_name=`sed 's/event_//'`
    else
        local event_handler_name=""
    fi
    mail -s "${HOSTNAME:-`hostname -s`}: $event_handler_name Event Handler Error" $MAILTO < $LOGFILE
    exit $CRITICAL
}
