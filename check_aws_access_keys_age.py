#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2019-12-16 11:37:15 +0000 (Mon, 16 Dec 2019)
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

Nagios Plugin to check the age of AWS Access Keys to find and remove/rotate old keys as per best practices

Iterates all AWS IAM users so if you have a lot of users you will need to increase the --timeout

Verbose mode will output the users, key status, key created date and age in days

Validated compared to xls report download from Trusted Advisor -> Security -> IAM Access Key Rotation

Uses the Boto python library, read here for the list of ways to configure your AWS credentials:

    https://boto3.amazonaws.com/v1/documentation/api/latest/guide/configuration.html

See also:

    aws_users_access_key_age.py - from DevOps Python Tools repo if you just want a list
                                - https://github.com/harisekhon/devops-python-tools

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
    from harisekhon.utils import log, plural, validate_float
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.0'


class AWSAccessKeyAge(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(AWSAccessKeyAge, self).__init__()
        # Python 3.x
        # super().__init__()
        self.age = None
        self.now = None
        self.only_active_keys = False
        self.count_old_keys = 0
        self.msg = 'AWSAccessKeyAge msg not defined'
        self.ok()

    def add_options(self):
        self.add_opt('-a', '--age', default=365, type=int,
                     help='Return warning on keys older than N days (default 365)')
        self.add_opt('-o', '--only-active', action='store_true', help='Only count keys with Active status')

    def process_args(self):
        self.no_args()
        self.only_active_keys = self.get_opt('only_active')
        self.age = self.get_opt('age')
        validate_float(self.age, 'age')
        self.age = int(self.age)

    def run(self):
        iam = boto3.client('iam')
        user_paginator = iam.get_paginator('list_users')
        self.now = datetime.datetime.utcnow()
        count = 0
        for users_response in user_paginator.paginate():
            for user_item in users_response['Users']:
                username = user_item['UserName']
                key_paginator = iam.get_paginator('list_access_keys')
                for keys_response in key_paginator.paginate(UserName=username):
                    self.process_keys(keys_response, username)
                    count += 1
        old_count = self.count_old_keys
        if old_count:
            self.warning()
        self.msg = '{} AWS access key{} older than {} days'.format(old_count, plural(old_count), self.age)
        self.msg += ' | num_old_access_keys={} num_access_keys={}'.format(old_count, count)

    def process_keys(self, keys_response, username):
        #assert not keys_response['IsTruncated']
        for access_key_item in keys_response['AccessKeyMetadata']:
            assert username == access_key_item['UserName']
            status = access_key_item['Status']
            if self.only_active_keys and status != 'Active':
                continue
            create_date = access_key_item['CreateDate']
            # already cast to datetime.datetime with tzinfo
            #create_datetime = datetime.datetime.strptime(create_date, '%Y-%m-%d %H:%M:%S%z')
            # removing tzinfo for comparison to avoid below error
            # - both are UTC and this doesn't make much difference anyway
            # TypeError: can't subtract offset-naive and offset-aware datetimes
            age_timedelta = self.now - create_date.replace(tzinfo=None)
            age_days = ceil(age_timedelta.total_seconds() / 86400.0)
            if age_days < self.age:
                continue
            log.info('{user:20}\t{status:8}\t{date}\t ({days} days)'.format(
                user=username,
                status=status,
                date=create_date,
                days=age_days))
            self.count_old_keys += 1


if __name__ == '__main__':
    AWSAccessKeyAge().main()
