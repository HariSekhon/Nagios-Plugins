#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2019-12-16 17:56:43 +0000 (Mon, 16 Dec 2019)
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

Nagios Plugin to check the age of AWS IAM user accounts last password used to find and remove old users

Iterates all AWS IAM users so if you have a lot of users you will need to increase the --timeout

Verbose mode will output the users, date of last password use and days ago

Uses the Boto python library, read here for the list of ways to configure your AWS credentials:

    https://boto3.amazonaws.com/v1/documentation/api/latest/guide/configuration.html

See also:

    aws_users_pw_last_used.sh - from DevOps Bash Tools repo if you just want a list
                              - https://github.com/harisekhon/devops-bash-tools

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import datetime
import os
import sys
import traceback
from math import ceil
import boto3
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, validate_float
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1.0'


class AWSUsersPwLastUsed(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(AWSUsersPwLastUsed, self).__init__()
        # Python 3.x
        # super().__init__()
        self.age = None
        self.msg = 'AWSUsersPwLastUsed msg not defined'
        self.ok()

    def add_options(self):
        self.add_opt('-a', '--age', default=365, type=int,
                     help='Return warning on keys older than N days (default 365)')

    def process_args(self):
        self.no_args()
        self.age = self.get_opt('age')
        validate_float(self.age, 'age')
        self.age = int(self.age)

    def run(self):
        iam = boto3.client('iam')
        user_paginator = iam.get_paginator('list_users')
        now = datetime.datetime.utcnow()
        count = 0
        for users_response in user_paginator.paginate():
            for user_item in users_response['Users']:
                log.debug('%s', user_item)
                username = user_item['UserName']
                if not 'PasswordLastUsed' in user_item:
                    log.debug('no PasswordLastUsed field for user %s, skipping...', username)
                    continue
                # already cast to datetime.datetime with tzinfo
                password_last_used = user_item['PasswordLastUsed']
                # removing tzinfo for comparison to avoid below error
                # - both are UTC and this doesn't make much difference anyway
                # TypeError: can't subtract offset-naive and offset-aware datetimes
                age_timedelta = now - password_last_used.replace(tzinfo=None)
                age_days = ceil(age_timedelta.total_seconds() / 86400.0)
                if age_days < self.age:
                    continue
                log.info('{user:20}\t{date}\t ({days} days)'.format(
                    user=username,
                    date=password_last_used,
                    days=age_days))
                count += 1
        if count:
            self.warning()
        self.msg = '{} AWS IAM users with passwords last used more than {} days ago'.format(count, self.age)
        self.msg += ' | num_old_users={}'.format(count)


if __name__ == '__main__':
    AWSUsersPwLastUsed().main()
