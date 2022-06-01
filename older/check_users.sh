#!/usr/bin/env bash
#
#  Author: Hari Sekhon
#  Date: 2007-03-02 11:59:38 +0000 (Fri, 02 Mar 2007)
#
#  https://github.com/HariSekhon/Nagios-Plugins
#
#  License: see accompanying LICENSE file
#

# Nagios Plugin to list all currently logged on users to a system.

version=0.2

# This makes coding much safer as a varible typo is caught
# with an error rather than passing through
set -u

# Note: resisted urge to use <<<, instead sticking with |
# in case anyone uses this with an older version of bash
# so no bash bashers please on this

# Standard Nagios exit codes
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

usage(){
    echo "usage: ${0##*/} [--simple] [ --mandatory username ] [ --unauthorized username ] [ --whitelist username ]"
    echo
    echo "returns a list of users on the local machine"
    echo
    echo "   -s, --simple show users without the number of sessions"
    echo "   -m username, --mandatory username,username2,username3..."
    echo "                Mandatory users. Return CRITICAL if any of these users are not"
    echo "                currently logged in"
    echo "   -u username, --unauthorized username,username2,username3..."
    echo "                Unauthorized users. Returns CRITICAL if any of these users are"
    echo "                logged in. This can be useful if you have a policy that states"
    echo "                that you may not have a root shell but must instead only use "
    echo "                'sudo command'. Specifying '-u root' would alert on root having"
    echo "                a session and hence catch people violating such a policy."
    echo "   -w username, --whitelist username,username2,username3..."
    echo "                Whitelist users. This is exceptionally useful. If you define"
    echo "                a bunch of users here that you know you use, and suddenly"
    echo "                there is a user session open for another account it could"
    echo "                alert you to a compromise. If you run this check say every"
    echo "                3 minutes, then any attacker has very little time to evade"
    echo "                detection before this trips."
    echo
    echo "                -m,-u and -w can be specified multiple times for multiple users"
    echo "                or you can use a switch a single time with a comma separated"
    echo "                list."
    echo
    echo "   -V --version Print the version number and exit"
    echo
    exit $UNKNOWN
}

simple=""
mandatory_users=""
unauthorized_users=""
whitelist_users=""

while [ "$#" -ge 1 ]; do
    case "$1" in
        -h|--help)  usage
                    ;;
     -V|--version)  echo $version
                    exit $UNKNOWN
                    ;;
      -s|--simple)  simple=true
                    ;;
   -m|--mandatory)  if [ "$#" -ge 2 ]; then
                        if [ -n "$mandatory_users" ]; then
                            mandatory_users="$mandatory_users $2"
                        else
                            mandatory_users="$2"
                        fi
                        shift
                    else
                        usage
                    fi
                    ;;
-u|--unauthorized)  if [ "$#" -ge 2 ]; then
                        if [ -n "$unauthorized_users" ]; then
                            unauthorized_users="$unauthorized_users $2"
                        else
                            unauthorized_users="$2"
                        fi
                        shift
                    else
                        usage
                    fi
                    ;;
   -w|--whitelist)  if [ "$#" -ge 2 ]; then
                        if [ -n "$whitelist_users" ]; then
                            whitelist_users="$whitelist_users $2"
                        else
                            whitelist_users="$2"
                        fi
                        shift
                    else
                        usage
                    fi
                    ;;
                *)  usage
                    ;;
    esac
    shift
done

mandatory_users="$(tr ',' ' ' <<< "$mandatory_users")"
unauthorized_users="$(tr ',' ' ' <<< "$unauthorized_users")"
whitelist_users="$(tr ',' ' ' <<< "$whitelist_users")"

# Must be a list of usernames only.
userlist="$(who | grep -v '^ *$' | awk '{print $1}' | sort)"
errormsg=""
exitcode=$OK

if [ -n "$userlist" ]; then
    if [ -n "$mandatory_users" ]; then
        missing_users=""
        for user in $mandatory_users; do
            if ! echo "$userlist"|grep "^$user$" >/dev/null 2>&1; then
                missing_users="$missing_users $user"
                exitcode=$CRITICAL
            fi
        done
        while read -r user; do
            # shellcheck disable=SC2089
            errormsg="${errormsg}user '$user' not logged in. "
        done < <(tr ' ' '\n' <<< "$missing_users" | sort -u)
    fi

    if [ -n "$unauthorized_users" ]; then
        blacklisted_users=""
        for user in $unauthorized_users; do
            if echo "$userlist"|sort -u|grep "^$user$" >/dev/null 2>&1; then
                blacklisted_users="$blacklisted_users $user"
                exitcode=$CRITICAL
            fi
        done
        while read -r user; do
            errormsg="${errormsg}Unauthorized user '$user' is logged in! "
        done < <(tr ' ' '\n' <<< "$blacklisted_users" | sort -u)
    fi

    if [ -n "$whitelist_users" ]; then
        unwanted_users=""
        while read -r user; do
            if ! tr ' ' '\n' <<< "$whitelist_users" | grep -q "^$user$"; then
                unwanted_users="$unwanted_users $user"
                exitcode=$CRITICAL
            fi
        done < <(sort -u <<< "$userlist")
        while read -r user; do
            errormsg="${errormsg}Unauthorized user '$user' detected! "
        done < <(tr ' ' '\n' <<< "$unwanted_users" | sort -u)
    fi

    if [ "$simple" == "true" ]
        then
        finallist="$(uniq <<< "$userlist")"
    else
        finallist="$(uniq -c <<< "$userlist" | awk '{print $2"("$1")"}')"
    fi
else
    finallist="no users logged in"
fi

if [ "$exitcode" -eq $OK ]; then
    # shellcheck disable=SC2086,SC2027,SC2090
    echo "USERS OK:" $finallist
    exit $OK
elif [ "$exitcode" -eq $WARNING ]; then
    # shellcheck disable=SC2086,SC2027,SC2090
    echo "USERS WARNING:" $errormsg"[users: "$finallist"]"
    exit $WARNING
elif [ "$exitcode" -eq $CRITICAL ]; then
    # shellcheck disable=SC2086,SC2027,SC2090
    echo "USERS CRITICAL:" $errormsg"[users: "$finallist"]"
    exit $CRITICAL
else
    # shellcheck disable=SC2086,SC2027,SC2090
    echo "USERS UNKNOWN:" $errormsg"[users: "$finallist"]"
    exit $UNKNOWN
fi

exit $UNKNOWN
