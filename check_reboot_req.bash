#!/bin/bash
#
# Check if reboot is required plugin for Nagios for Debian/Ubuntu Systems
# Written by Senthil Nathan 
# Last Modified: 10/31/2023
#
# Usage: ./check_reboot_req -w 0 -c 2
#
# Description:
#
# This plugin will send an alert if the servers needs to be rebooted
#
# Output:
#
# System OK
# Reboot required
#
#
# Notes:
#
# Update RFILENAME as required
#
#

ECHO="/bin/echo"
GREP="/bin/egrep"
DIFF="/usr/bin/diff"
TAIL="/usr/bin/tail"
CAT="/bin/cat"
RM="/bin/rm"
CHMOD="/bin/chmod"
TOUCH="/bin/touch"

PROGNAME=`/usr/bin/basename $0`
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`
REVISION="1.0"

. $PROGPATH/utils.sh

RFILENAME=/var/run/reboot-required

print_usage() {
    echo "Without parameters defaults to -w 0 and -c 1"
    echo "Usage: $PROGNAME"
    echo "Usage: $PROGNAME -w days -c days"
    echo "Usage: $PROGNAME --help"
    echo "Usage: $PROGNAME --version"
}

print_help() {
    print_revision $PROGNAME $REVISION
    echo ""
    print_usage
    echo ""
    echo "Plugin for Nagios to alert if system needs a reboot"
    echo ""
    support
}

# Grab the command line arguments

exitstatus=$STATE_WARNING #default
while test -n "$1"; do
    case "$1" in
        --help)
            print_help
            exit $STATE_OK
            ;;
        -h)
            print_help
            exit $STATE_OK
            ;;
        --version)
            print_revision $PROGNAME $REVISION
            exit $STATE_OK
            ;;
        -V)
            print_revision $PROGNAME $REVISION
            exit $STATE_OK
            ;;
        --warning)
            warn=$2
            shift
            ;;
        -w)
            warn=$2
            shift
            ;;
        --critical)
            crit=$2
            shift
            ;;
        -c)
            crit=$2
            shift
            ;;
        -x)
            exitstatus=$2
            shift
            ;;
        --exitstatus)
            exitstatus=$2
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            print_usage
            exit $STATE_UNKNOWN
            ;;
    esac
    shift
done

# Check begins here
if [ -z $warn ]; then
    declare -i warn=0
fi
if [ -z $crit ]; then
    declare -i crit=1
fi
#
if [ -f "${RFILENAME}" ]; then
    CDATE=$(date +%s)
    FDATE=`stat -c %Y -- "${RFILENAME}"`
    DDIFF=$(($CDATE-$FDATE))
    DIFFDAYS=$((DDIFF/86400))
    if [ $DIFFDAYS -ge $crit ]; then
        exitstatus=$STATE_CRITICAL
    elif [ $DIFFDAYS -ge $warn ]; then
        exitstatus=$STATE_WARNING
    else
        exitstatus=$STATE_OK
    fi
    echo "Reboot required"
else
    echo "System OK"
    exitstatus=$STATE_OK
fi
exit $exitstatus
