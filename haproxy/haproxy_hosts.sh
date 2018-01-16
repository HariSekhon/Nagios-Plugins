#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-01-16 17:23:27 +0000 (Tue, 16 Jan 2018)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

# Script to extract all server addresses to be able to put them in /etc/hosts for testing

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

grep -h '^[[:space:]]*server' *.cfg */*.cfg |
awk '{print $3}' |
sed 's/:.[[:digit:]]*//' |
sort -u
