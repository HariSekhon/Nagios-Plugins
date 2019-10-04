#!/bin/sh
#
#  Author: Hari Sekhon
#  Date: A Very Long Time Ago (2007 - 2010?)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# This is a generic wrapper to allow you to make any service check into a
# passive service check without the need for writing wrappers for every
# check since that is a waste of time and effort. You can put everything
# you need on one line in order to submit a passive service check for Nagios

set -u
srcdir=`dirname $0`
version=0.8

# Fill in the following 3 variables below if if you do not want to have to
# repeatedly put your Nagios server, send_nsca path and send_nsca.cfg on the
# command line

# This should be the IP address of your Nagios/NSCA server. Can use DNS name
# but not generally as good to do that. If you DNS server is down, your passive
# service check results will not reach the NSCA/Nagios server and will
# therefore go stale causing warning/critical conditions.
NAGIOS_SERVER="x.x.x.x"

NAGIOS_PIPE="/var/log/nagios/rw/nagios.cmd"

# This should be the full path to the SEND_NSCA binary. Use this only if your
# send _nsca program is not in the PATH of the user executing the nsca_wrapper
SEND_NSCA="/usr/sbin/send_nsca"

# This should be the path to your send_nsca.cfg or equivalent config. This
# config is necessary to tell the send_nsca program how to connect to your
# NSCA daemon on your Nagios server. It contains the port and the connection
# password. If you do not set this, this script will look for send_nsca.cfg
# in the same directory as this script is located.
SEND_NSCA_CONFIG=""

cmd=""
host=""
local_passive=false
nagios_pipe=""
nagios_server=""
quiet_mode=false
return_plugin_code=false
send_nsca=""
send_nsca_config=""
service=""

die(){
    echo "$@"
    exit 3
}

usage(){
    [ "$#" -gt 0 ] && echo "$@" && echo
    die "usage: ${0##*/} -H \$HOSTNAME$ -S \$SERVICENAME$ -C '/path/to/plugin/check_stuff -arg1 -arg2 ... -argN' <options>

-H \$HOSTNAME$              The Host name of the server being checked by the
                           plugin. It should be written exactly as it appears in
                           the Nagios config/interface.
-S \$SERVICENAME$           The name of the service that is being checked by the
                           plugin. It should be written exactly as it appears
                           in the Nagios config/interface.
-C COMMAND                 The command line to run the plugin (should be quoted)
                           BE VERY CAREFUL WITH THIS. IT WILL EXECUTE USING SHELL


Optional:

    Send Result to Local Nagios

-l                         Send the passive result to the local nagios installation
                           instead of via NSCA.
-p                         Location of the Nagios cmd pipe (defaults to '$NAGIOS_PIPE')


    Send Result to Remote Nagios via NSCA

-N IPADDRESS               The IP address of the nagios/nsca server to send the
                           result of the plugin to. This should be an IP instead
                           of a DNS name. If you use a DNS name here and your
                           dns service breaks, then all your passive checks will
                           fail as they won't find the nsca server.
-b /path/to/send_nsca      The path to the send_nsca binary. Optional. Only
                           necessary if send_nsca is not in your default PATH.
-c /path/to/send_nsca.cfg  The path to the nsca config file. By default it will
                           look for this in the same directory as this wrapper
                           program. If the send_nsca config file is named
                           differently or located somewhere else, you must'
                           specify the path with this switch.
-e                         exit with the return code of the plugin rather than
                           the return code of the sending to the NSCA daemon

    Other Options

-q                         quiet mode. Do not show any output
-V --version               Show version and exit
-h --help                  Show this help
"
}

[ $# -eq 0 ] && usage

until [ "$#" -lt 1 ]; do
    case "$1" in
        -h|--help)  usage
                    ;;
               -H)  host="${2:-}"
                    shift
                    ;;
               -S)  service="${2:-}"
                    shift
                    ;;
               -N)  nagios_server="${2:-}"
                    shift
                    ;;
               -C)  cmd="${2:-}"
                    shift
                    ;;
               -b)  send_nsca="${2:-}"
                    shift
                    ;;
               -c)  send_nsca_config="${2:-}"
                    shift
                    ;;
               -l)  local_passive=true
                    ;;
               -p)  nagios_pipe="${2:-}"
                    shift
                    ;;
               -e)  return_plugin_code=true
                    ;;
               -q)  quiet_mode=true
                    ;;
     -V|--version)  die $version
                    ;;
                *)  usage
                    ;;
    esac
    shift
done


[ -n "$host" ]     || die "You must supply a Host name exactly as it appears in Nagios"
[ -n "$service" ]  || die "You must supply a Service name exactly as it appears in Nagios"
[ -n "$cmd" ]      || die "You must supply a command to execute"

[ "$local_passive" = "true" -a -n "$nagios_server" ] && usage "Cannot specify local check and nagios server to send passive check to, they are mutually exclusive"

if [ -z "$nagios_server" ]; then
    if [ -n "$NAGIOS_SERVER" ]; then
        nagios_server="$NAGIOS_SERVER"
    else
        die "You must supply an address for the nagios server"
    fi
fi

if [ "$local_passive" = "true" ]; then
    [ -n "$nagios_pipe" ] || nagios_pipe=$NAGIOS_PIPE
    [ -e "$nagios_pipe" ] || die "Nagios cmd pipe not found: '$nagios_pipe'"
    [ -p "$nagios_pipe" ] || die "Nagios cmd pipe error: '$nagios_pipe' is not a named pipe, aborting for safety"
    [ -w "$nagios_pipe" ] || die "Nagios cmd pipe error: '$nagios_pipe' is not writeable"
else
    if [ -z "$send_nsca_config" ]; then
        if [ -n "$SEND_NSCA_CONFIG" ]; then
            send_nsca_config="$SEND_NSCA_CONFIG"
        else
            [ -f "$srcdir/send_nsca.cfg" ] && send_nsca_config="$srcdir/send_nsca.cfg"
            [ -f "$srcdir/../send_nsca.cfg" ] && send_nsca_config="$srcdir/../send_nsca.cfg"
        fi
    fi

    if [ -z "$send_nsca" ]; then
        if [ -n "$SEND_NSCA" ]; then
            send_nsca="$SEND_NSCA"
        else
            # assume send_nsca is in the PATH
            send_nsca="send_nsca"
        fi
    fi

    # Make sure we have send_nsca before we begin
    if [ "$send_nsca" = "send_nsca" ]; then
        if ! type -P "$send_nsca" >/dev/null 2>&1; then
            die "send_nsca was not found in the PATH!"
        fi
    else
        if [ ! -x  "$send_nsca" ]; then
            if [ -f "$send_nsca" ]; then
                die "send_nsca was found but is not executable. You may need to chmod +x it first"
            else
                die "send_nsca was not found at the expected place of '$send_nsca'"
            fi
        fi
    fi

    # Check for the presence of the nsca config file which is needed to run send_nsca
    if [ ! -f "$send_nsca_config" ]; then
        die "The send_nsca config file '$send_nsca_config' was not found. Please use the -c switch to specify it's location"
    elif [ ! -r "$send_nsca_config" ]; then
        die "The send_nsca config file cannot be read, please check permissions..."
    fi
fi

# Small safety check, this won't stop a kid.
# Might help a careless person though (yeah right)
dangerous_commands="rm rmdir dd del mv cp halt shutdown reboot init telinit kill killall pkill"
for x in $cmd; do
    for y in $dangerous_commands; do
        if [ "$x" = "$y" ]; then
            echo "DANGER: the $y command was found in the string given to execute under nsca_wrapper, aborting..."
            exit 3
        fi
    done
done

which ${cmd%% *} >/dev/null 2>&1 || die "Command not found: ${cmd%% *}"
output="`$cmd 2>&1`"
result=$?
[ "$quiet_mode" = "true" ] || echo "$output"
output="`echo "$output" | sed 's/%/%%/g'`"

if [ "$local_passive" = "true" ]; then
    nagios_result="PROCESS_SERVICE_CHECK_RESULT;$host;$service;$result;$output"
    printf "[%lu] $nagios_result\n" `date +%s` >> "$nagios_pipe"
else
    send_output=`printf "$host\t$service\t$result\t$output\n" | $send_nsca -H $nagios_server -c $send_nsca_config 2>&1`
    send_result=$?
    [ "$quiet_mode" = "true" ] && echo "Sending to NSCA daemon: $send_output"
fi

if [ -n "$return_plugin_code" -o "$local_passive" = "true" ]; then
    exit "$result"
else
    exit "$send_result"
fi
