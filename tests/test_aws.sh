#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-01-08 17:19:57 +0000 (Wed, 08 Jan 2020)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "A W S"

echo "running ./check_aws_api_ping.py to figure out if access key and secret key are available and working"
hr
if ./check_aws_api_ping.py >/dev/null; then
    run check_aws_api_ping.py

    run_fail "0 1" ./check_aws_access_keys_age.py

    run ./check_aws_access_keys_disabled.py

    run ./check_aws_ec2_instance_count.py

    run ./check_aws_ec2_instance_states.py --max-stopped 100

    run ./check_aws_password_policy.py --password-length 12 --password-age 60 --password-reuse 10

    run ./check_aws_root_account.py

    run ./check_aws_user_last_used.py

    run_fail "0 1" ./check_aws_users_mfa_enabled.py

    run_fail "0 1" ./check_aws_users_password_last_used.py

    run_fail "0 1" ./check_aws_users_unused.py
fi

# $run_count assigned in lib/utils.sh and incremented by run()
# shellcheck disable=SC2154
echo "Completed $run_count AWS tests"
echo
echo "All AWS tests passed successfully"
echo
echo
