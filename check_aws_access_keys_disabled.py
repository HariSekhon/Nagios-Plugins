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

Nagios Plugin to check for any disabled AWS Access Keys which should probably be removed

Iterates all AWS IAM users so if you have a lot of users you will need to increase the --timeout

Verbose mode will output the users, key status and key created date

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

import os
import sys
import traceback
import boto3
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, plural
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.0'


class AWSAccessKeysDisabled(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(AWSAccessKeysDisabled, self).__init__()
        # Python 3.x
        # super().__init__()
        self.disabled_access_key_count = 0
        self.msg = 'AWSAccessKeysDisabled msg not defined'
        self.ok()

    def run(self):
        iam = boto3.client('iam')
        user_paginator = iam.get_paginator('list_users')
        count = 0
        for users_response in user_paginator.paginate():
            for user_item in users_response['Users']:
                username = user_item['UserName']
                key_paginator = iam.get_paginator('list_access_keys')
                for keys_response in key_paginator.paginate(UserName=username):
                    self.process_keys(keys_response, username)
                    count += 1
        disabled_count = self.disabled_access_key_count
        if disabled_count:
            self.warning()
        self.msg = '{} AWS access key{} disabled'.format(disabled_count, plural(disabled_count))
        self.msg += ' | num_disabled_access_keys={} num_access_keys={}'.format(disabled_count, count)

    def process_keys(self, keys_response, username):
        #assert not keys_response['IsTruncated']
        for access_key_item in keys_response['AccessKeyMetadata']:
            assert username == access_key_item['UserName']
            status = access_key_item['Status']
            create_date = access_key_item['CreateDate']
            log.info('{user:20}\t{status:8}\t{date}'.format(
                user=username,
                status=status,
                date=create_date))
            # alternative is 'Inactive'
            if status != 'Active':
                self.disabled_access_key_count += 1


if __name__ == '__main__':
    AWSAccessKeysDisabled().main()
