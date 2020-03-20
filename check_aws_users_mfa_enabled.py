#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-01-08 11:35:39 +0000 (Wed, 08 Jan 2020)
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

Nagios Plugin to detect AWS IAM users without MFA enabled

Auto excludes users without passwords

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
from io import StringIO
import boto3
from botocore.exceptions import ClientError
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.0'


class AWSUsersMFA(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(AWSUsersMFA, self).__init__()
        # Python 3.x
        # super().__init__()
        self.days = None
        self.now = None
        self.msg = 'AWSUsersMFA msg not defined'
        self.ok()

    def process_args(self):
        self.no_args()

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
        assert headers[3] == 'password_enabled'
        assert headers[7] == 'mfa_active'
        user_count = 0
        users_without_mfa_count = 0
        for row in csvreader:
            if not self.check_user_mfa(row):
                users_without_mfa_count += 1
            user_count += 1
        if users_without_mfa_count:
            self.warning()
        self.msg = 'AWS users with passwords without MFA enabled = {} out of {} users'\
                   .format(users_without_mfa_count, user_count)
        self.msg += ' | num_users_without_mfa={} num_users={}'.format(users_without_mfa_count, user_count)

    @staticmethod
    def check_user_mfa(row):
        log.debug('processing user: %s', row)
        user = row[0]
        password_enabled = row[3]
        mfa = row[7]
        log.debug('user: %s, password enabled: %s, mfa enabled: %s', user, password_enabled, mfa)
        if mfa == 'true':
            return True
        elif password_enabled == 'false':
            return True
        return False


if __name__ == '__main__':
    AWSUsersMFA().main()
