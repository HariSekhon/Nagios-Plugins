#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-02-22 22:53:05 +0000 (Sat, 22 Feb 2020)
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
srcdir="$(dirname "$0")"

sudo=""
[ $EUID -eq 0 ] || sudo=sudo

if [ "$(uname -s)" != Darwin ]; then
    echo "OS is not Mac, skipping mysql_config workaround, installing DBD::mysql normally via cpanm"
    "$srcdir/../bash-tools/perl_cpanm_install_if_absent.sh" DBD::mysql
    exit 0
fi

if perl -e 'use DBD::mysql;' &>/dev/null; then
    echo "Perl DBD::mysql already installed, skipping mysql_config workaround"
    exit 0
fi

set +e
mysql_config="$(type -P mysql_config)"
set -e
if [ -z "$mysql_config" ]; then
    echo "mysql_config not found in \$PATH!! ($PATH)"
    exit 1
fi

"$mysql_config" || :

echo
if ! mysql_config | grep -q -- '--libs.*-lmysqlclient.*-L.*openssl'; then
    echo "patching mysql_config: $mysql_config"
    # shellcheck disable=SC2016
    $sudo sed -ibak 's/^libs="$libs/libs="$libs -lmysqlclient -L\/usr\/local\/opt\/openssl\/lib/' "$mysql_config"
    echo
    "$mysql_config" || :
    echo
else
    echo "mysql_config patching not needed"
fi
echo

set +e -x
brew install --force mysql openssl
brew unlink mysql
brew install --force mysql-connector-c
brew link --force --overwrite mysql-connector-c
set -e +x

# installing DBI module even if provided by system since DBD-mysql fails without it:
#
# cc -c  -I/System/Library/Perl/Extras/5.18/darwin-thread-multi-2level/auto/DBI -I/usr/local/include/mysql -DDBD_MYSQL_WITH_SSL -g  -g -pipe -fno-common -DPERL_DARWIN -fno-strict-aliasing -fstack-protector -Os   -DVERSION=\"4.050\" -DXS_VERSION=\"4.050\"  -iwithsysroot "/System/Library/Perl/5.18/darwin-thread-multi-2level/CORE"   dbdimp.c
# In file included from dbdimp.c:15:
# ./dbdimp.h:20:10: fatal error: 'DBIXS.h' file not found
# #include <DBIXS.h>  /* installed by the DBI module                        */
#
# system provided DBI module's location on Mac isn't found, but is for example:
#
# /Library/Developer/CommandLineTools/SDKs/MacOSX10.14.sdk/System/Library/Perl/Extras/5.18/darwin-thread-multi-2level/auto/DBI/DBIXS.h
# /Library/Developer/CommandLineTools/SDKs/MacOSX10.15.sdk/System/Library/Perl/Extras/5.18/darwin-thread-multi-2level/auto/DBI/DBIXS.h
#
# so could add some hackiness to the path or otherwise just install DBI manually where it'll be naturally found
"$srcdir/../bash-tools/perl_cpanm_install.sh" DBI

"$srcdir/../bash-tools/perl_cpanm_install_if_absent.sh" DBD::mysql
