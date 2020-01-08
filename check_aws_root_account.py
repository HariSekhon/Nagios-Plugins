#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-01-07 14:35:44 +0000 (Tue, 07 Jan 2020)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check the AWS root account has MFA enabled and no access keys as per best practices

Uses the Boto python library, read here for the list of ways to configure your AWS credentials:

    https://boto3.amazonaws.com/v1/documentation/api/latest/guide/configuration.html

See also other AWS tools in this repo and the adjacent DevOps Python and Bash tools repos

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import sys
import traceback
import boto3
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, jsonpp, plural
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.0'


class CheckAWSRootAccount(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAWSRootAccount, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'CheckAWSRootAccount msg not defined'
        self.ok()

    def process_args(self):
        self.no_args()

    # must be an instance method for inheritance subclassing to match
    # pylint: disable=no-self-use
    def run(self):
        iam = boto3.client('iam')
        log.info('getting account summary')
        _ = iam.get_account_summary()
        log.debug('%s', jsonpp(_))
        account_summary = _['SummaryMap']
        mfa_enabled = account_summary['AccountMFAEnabled']
        access_keys = account_summary['AccountAccessKeysPresent']
        if access_keys or not mfa_enabled:
            self.warning()
        self.msg = 'AWS root account MFA enabled = {}{}'.format(bool(mfa_enabled), ' (!)' if not mfa_enabled else "")
        self.msg += ', {} access key{} found{}'.format(access_keys, plural(access_keys), ' (!)' if access_keys else "")


if __name__ == '__main__':
    CheckAWSRootAccount().main()
