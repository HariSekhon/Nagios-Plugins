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

Nagios Plugin to find AWS IAM user accounts that haven't been used in the last N days

Excludes root account which should not normally be used and should have a higher age

Default days is 90 as per the CIS AWS Security whitepaper

Generates an IAM credential report, then parses it to determine the time since each user's password
and access keys were last used, using the most recent timestamps among the password and access keys
one as the last used age of the account

Requires iam:GenerateCredentialReport on resource: *

Uses the Boto python library, read here for the list of ways to configure your AWS credentials:

    https://boto3.amazonaws.com/v1/documentation/api/latest/guide/configuration.html

See also DevOps Python Tools and DevOps Bash Tools repos which have more similar AWS tools

- https://github.com/harisekhon/devops-python-tools
- https://github.com/harisekhon/devops-bash-tools

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import csv
import os
import sys
import time
import traceback
from datetime import datetime
from io import StringIO
from math import floor
import boto3
from botocore.exceptions import ClientError
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, plural, validate_int
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.0'


class AWSUsersUnused(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(AWSUsersUnused, self).__init__()
        # Python 3.x
        # super().__init__()
        self.days = None
        self.now = None
        self.msg = 'AWSUsersUnused msg not defined'
        self.ok()

    def add_options(self):
        self.add_opt('-d', '--days', default=90, type=int,
                     help='Warn if accounts present that have been unused in the last N days (default: 90)')

    def process_args(self):
        self.no_args()
        self.days = self.get_opt('days')
        validate_int(self.days, 'days')

    def run(self):
        iam = boto3.client('iam')
        log.info('generating credentials report')
        while True:
            result = iam.generate_credential_report()
            log.debug('%s', result)
            if result['State'] == 'COMPLETE':
                log.info('credentials report generated')
                break
            log.info('waiting for credentials report')
            time.sleep(1)
        try:
            result = iam.get_credential_report()
        except ClientError as _:
            raise
        csv_content = result['Content']
        log.debug('%s', csv_content)
        filehandle = StringIO(unicode(csv_content))
        filehandle.seek(0)
        csvreader = csv.reader(filehandle)
        headers = next(csvreader)
        assert headers[0] == 'user'
        assert headers[4] == 'password_last_used'
        assert headers[10] == 'access_key_1_last_used_date'
        assert headers[15] == 'access_key_2_last_used_date'
        user_count = 0
        old_user_count = 0
        self.now = datetime.utcnow()
        for row in csvreader:
            if not self.check_user_last_used(row):
                old_user_count += 1
            user_count += 1
        if old_user_count:
            self.warning()
        self.msg = '{} AWS user{} not used in more than {} days'.format(
            old_user_count, plural(old_user_count), self.days)
        self.msg += ' | num_old_users={} num_users={}'.format(old_user_count, user_count)

    def check_user_last_used(self, row):
        log.debug('processing user: %s', row)
        user = row[0]
        password_last_used = row[4]
        access_key_1_last_used_date = row[10]
        access_key_2_last_used_date = row[15]
        log.debug('user: %s, password_last_used: %s, access_key_1_last_used_date: %s, access_key_2_last_used_date: %s',
                  user, password_last_used, access_key_1_last_used_date, access_key_2_last_used_date)
        min_age = None
        for _ in [password_last_used, access_key_1_last_used_date, access_key_2_last_used_date]:
            if _ == 'N/A':
                continue
            # %z not working in Python 2.7 but we already know it's +00:00
            _datetime = datetime.strptime(_.split('+')[0], '%Y-%m-%dT%H:%M:%S')
            age_timedelta = self.now - _datetime.replace(tzinfo=None)
            age_days = int(floor(age_timedelta.total_seconds() / 86400.0))
            if min_age is None or age_days < min_age:
                min_age = age_days
        log.debug('user %s was last used %s days ago', user, min_age)
        if age_days <= self.days:
            return True
        return False


if __name__ == '__main__':
    AWSUsersUnused().main()
