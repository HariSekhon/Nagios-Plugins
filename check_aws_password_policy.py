#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#  args: --password-length 12 --password-age 60 --password-reuse 10
#
#  Author: Hari Sekhon
#  Date: 2020-01-08 10:37:01 +0000 (Wed, 08 Jan 2020)
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

Nagios Plugin to check the AWS password policy requirements compliance with CIS Security Foundations Benchmark

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
    from harisekhon.utils import log, jsonpp, validate_int, WarningError
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1.0'


class CheckAWSPasswordPolicy(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAWSPasswordPolicy, self).__init__()
        # Python 3.x
        # super().__init__()
        # defaults taken from CIS Foundations Benchmark
        self.pw_min_len = 14
        self.pw_max_age = 90
        self.pw_reuse = 24
        self.pw_disallow_change = False
        self.msg = 'CheckAWSPasswordPolicy msg not defined'
        self.ok()

    def add_options(self):
        self.add_opt('-l', '--password-length', default=self.pw_min_len,
                     help='Minimum password length (default: {})'.format(self.pw_min_len))
        self.add_opt('-a', '--password-age', default=self.pw_max_age,
                     help='Maximum password age (default: {})'.format(self.pw_max_age))
        self.add_opt('-r', '--password-reuse', default=self.pw_reuse,
                     help='Minimum password reuse count (default: {})'.format(self.pw_reuse))
        self.add_opt('-c', '--password-disallow-change', action='store_true',
                     help="Don't allow users to change their passwords")

    def process_args(self):
        self.no_args()
        self.pw_min_len = self.get_opt('password_length')
        self.pw_max_age = self.get_opt('password_age')
        self.pw_reuse = self.get_opt('password_reuse')
        self.pw_disallow_change = self.get_opt('password_disallow_change')
        validate_int(self.pw_min_len, 'password min length')
        validate_int(self.pw_max_age, 'password max age')
        validate_int(self.pw_reuse, 'password_reuse')
        self.pw_min_len = int(self.pw_min_len)
        self.pw_max_age = int(self.pw_max_age)
        self.pw_reuse = int(self.pw_reuse)

    def run(self):
        iam = boto3.client('iam')
        log.info('getting password policy')
        try:
            _ = iam.get_account_password_policy()
        except iam.exceptions.NoSuchEntityException:
            raise WarningError('AWS no password policy defined!')

        log.debug('%s', jsonpp(_))
        password_policy = _['PasswordPolicy']
        pw_allow_users_change = password_policy['AllowUsersToChangePassword']
        pw_max_age = password_policy['MaxPasswordAge']
        pw_min_len = password_policy['MinimumPasswordLength']
        pw_reuse = password_policy['PasswordReusePrevention']
        for _ in [pw_max_age, pw_min_len, pw_reuse]:
            assert isinstance(_, int)
#        pw_expiry = password_policy['ExpirePasswords']
#        pw_hard_expiry = password_policy['HardExpiry']
#        pw_req_lowercase = password_policy['RequireLowercaseCharacters']
#        pw_req_uppercase = password_policy['RequireUppercaseCharacters']
#        pw_req_numbers = password_policy['RequireNumbers']
#        pw_req_symbols = password_policy['RequireSymbols']

        self.msg = 'AWS password policies: MinimumPasswordLength = {}'.format(pw_min_len)
        if pw_min_len < self.pw_min_len:
            self.warning()
            self.msg += ' (< {})'.format(self.pw_min_len)

        self.msg += ', MaxPasswordAge = {}'.format(pw_max_age)
        if pw_max_age < self.pw_max_age:
            self.warning()
            self.msg += ' (< {})'.format(self.pw_max_age)

        self.msg += ', PasswordReusePrevention = {}'.format(pw_reuse)
        if pw_reuse < self.pw_reuse:
            self.warning()
            self.msg += ' (< {})'.format(self.pw_reuse)

        boolean_fields = [
            'ExpirePasswords',
            'HardExpiry',
            'RequireLowercaseCharacters',
            'RequireUppercaseCharacters',
            'RequireNumbers',
            'RequireSymbols',
        ]

        for _ in boolean_fields:
            self.msg += ', {} = {}'.format(_, password_policy[_])
            assert isinstance(password_policy[_], bool)
            if not password_policy[_]:
                self.exclaim_and_warn()

        self.msg += ', AllowUsersToChangePassword = {}'.format(pw_allow_users_change)
        if self.pw_disallow_change:
            if pw_allow_users_change:
                self.exclaim_and_warn()
        else:
            if not pw_allow_users_change:
                self.exclaim_and_warn()

    def exclaim_and_warn(self):
        self.msg += ' (!)'
        self.warning()


if __name__ == '__main__':
    CheckAWSPasswordPolicy().main()
