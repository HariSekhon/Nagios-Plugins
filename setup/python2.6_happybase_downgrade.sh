#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#  (forked from Makefile)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# must downgrade happybase library to work on Python 2.6
#if [ "$$(python -c 'import sys; sys.path.append("pylib"); import harisekhon; print(harisekhon.utils.getPythonVersion())')" = "2.6" ]; then $(SUDO_PIP) pip install --upgrade "happybase==0.9"; fi
if python -V 2>&1 | grep -q '^Python 2.6'; then
    #$(SUDO_PIP) pip install --quiet --upgrade "happybase==0.9"
    PIP_OPTS="--quiet --upgrade" "$srcdir/../bash-tools/python_pip_install.sh" "happybase==0.9"
fi
