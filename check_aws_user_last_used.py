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

Nagios Plugin to warn if a given AWS IAM user account was used recently

Designed to alert on root account activity by default
as this is against best practice and may indicate a security breach

Generates an IAM credential report, then parses it to determine the time since the given user's
password and access keys were last used

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
    from harisekhon.utils import log, plural, validate_int, UnknownError
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.0'


class AWSuserLastUsed(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(AWSuserLastUsed, self).__init__()
        # Python 3.x
        # super().__init__()
        self.user = None
        self.days = None
        self.now = None
        self.msg = 'AWSuserLastUsed msg not defined'
        self.ok()

    def add_options(self):
        self.add_opt('-u', '--user', default='root', help='User to check on (default: root)')
        self.add_opt('-d', '--days', default=7, type=int,
                     help='Warn if the given account was used in the last N days (default: 7)')

    def process_args(self):
        self.no_args()
        self.user = self.get_opt('user')
        if self.user == 'root':
            self.user = '<root_account>'
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
        self.now = datetime.utcnow()
        found = False
        for row in csvreader:
            user = row[0]
            if user != self.user:
                continue
            found = True
            last_used_days = self.get_user_last_used_days(row)
        if not found:
            raise UnknownError('AWS user {} not found'.format(self.user))
        if last_used_days <= self.days:
            self.warning()
        if last_used_days == 0:
            self.msg = 'AWS user {} last used within the last day'.format(self.user)
        else:
            self.msg = 'AWS user {} last used {} day{} ago'.format(self.user, last_used_days, plural(last_used_days))
        self.msg += ' | last_used_days={};0;;{}'.format(last_used_days, self.days)

    def get_user_last_used_days(self, row):
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
        return age_days


if __name__ == '__main__':
    AWSuserLastUsed().main()
