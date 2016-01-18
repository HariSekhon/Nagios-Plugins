#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-11-28 17:47:25 +0000 (Sat, 28 Nov 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

set -euo pipefail
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

[ `uname -s` = "Linux" ] || exit 0

echo "
# ============================================================================ #
#                                   W h o i s
# ============================================================================ #
"

# Update: changed to run every time but with a small number of domains, it's better
# Don't run this all the time, give it a 50% chance of running to prevent getting blacklisted by registrars all the time
#if [ -n "${TRAVIS:-}" ]; then
#    if ! [ "$(($RANDOM % 10))" = 0 ]; then
#        echo "Skipping Whois checks (90% of the time in Travis to avoid blacklisting)"
#        exit 0
#    fi
#else
#    if ! [ "$(($RANDOM % 2))" = 0 ]; then
#        echo "Skipping Whois checks (50% of the time to avoid blacklisting)"
#        exit 0
#    fi
#fi

echo "Running Whois checks"

# random domains including some I used to work for to try to get some variation in registrars
domains="
cloudera.com
myspace.com
bskyb.com
sky.com
bnpparibas.com
specificmedia.com
experian.com
myspace.com.ee
"
# domains from tickets
domains="$domains
shomershabbatscouting.org
ymkatz.net
"

# generic TLDs, will generate google.$tld from this list
tlds="
ac
ag
am
asia
at
be
biz
ca
cc
ch
cl
cn
co.at
co.il
co.in
co.kr
co.nz
co.uk
com
com.au
com.br
com.cn
com.hk
com.mx
# .com.my times out
#com.my
com.pe
com.pl
com.pt
com.sg
com.tr
com.tw
com.ve
de
dk
eu
fi
fm
fr
# .gs times out
#gs
hk
hu
ie
in
info
# .io times out
#io
it
jp
kr
lu
me
mobi
ms
mx
# .my times outs
#my
net
net.au
net.br
net.cn
net.nz
nf
nl
nu
org
org.cn
org.nz
org.tw
org.uk
pl
ru
se
sg
sh
tc
tel
tl
tv
tv.br
tw
us
vg
xxx
"

#tlds_no_expiry="
#"

tlds_no_nameservers="
name
no
com.bo
idv.tw
"

domains="$domains
$(
    sed 's/#.*//;/^[[:space:]]*$/d' <<< "$tlds" |
    while read tld; do
        echo google.$tld
    done
)
"

#domains_no_expiry="
#$(
#    sed 's/#.*//;/^[[:space:]]*$/d' <<< "$tlds_no_expiry" |
#    while read tld; do
#        echo google.$tld
#    done
#)
#"

domains_no_nameservers="
$(
    sed 's/#.*//;/^[[:space:]]*$/d' <<< "$tlds_no_nameservers" |
    while read tld; do
        echo google.$tld
    done
)
"

echo "Testing Domains including expiry:"
for domain in $domains; do
    [ "$(($RANDOM % 20))" = 0 ] || continue
    printf "%-20s  " "$domain:"
    # don't want people with 25 days left on their domains raising errors here, setting thresholds lower to always pass
    set +eo pipefail
    output=`$perl -T $I_lib ./check_whois.pl -d $domain -w 10 -c 2 -vvv`
    result=$?
    echo "$output"
    if [ $result -ne 0 -a $result -eq 3 ]; then
        egrep -qi 'denied|quota|exceeded|blacklisted' <<< "$output" && continue
        exit 1
    fi
    set -e
done

# check_whois.pl has exception handling to give OK back in it's base code so this isn't needed
#echo "Testing Domains excluding expiry:"
#for domain in $domains_noexpiry; do
#    set +eo pipefail
#    output=`$perl -T $I_lib ./check_whois.pl -d $domain -w 10 -c 2 --no-expiry`
#    result=$?
#    echo "$output"
#    if [ $result -ne 0 -a $result -eq 3 ]; then
#        egrep -qi 'denied|quota|exceeded|blacklisted' <<< "$output" && continue
#        exit 1
#    fi
#    set -e
#done

echo "Testing Domains excluding nameservers:"
for domain in $domains_no_nameservers; do
    [ "$(($RANDOM % 20))" = 0 ] || continue
    set +eo pipefail
    output=`$perl -T $I_lib ./check_whois.pl -d $domain -w 10 -c 2 --no-nameservers -vvv`
    result=$?
    echo "$output"
    if [ $result -ne 0 -a $result -eq 3 ]; then
        egrep -qi 'denied|quota|exceeded|blacklisted' <<< "$output" && continue
        exit 1
    fi
    set -e
done

echo; echo
