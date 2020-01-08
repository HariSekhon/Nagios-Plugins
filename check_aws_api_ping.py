#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-01-08 14:55:35 +0000 (Wed, 08 Jan 2020)
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

Nagios Plugin to do a simple AWS API call to check access key credentials are working

Useful to use as a dependency check for all other AWS checks

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

import collections
import logging
import os
import sys
import traceback
import boto3
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, jsonpp, CriticalError
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.0'


class AWSAPIPing(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(AWSAPIPing, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'AWS API msg not defined'
        self.ok()

    def process_args(self):
        self.no_args()

    def run(self):
        log.info('testing AWS API call')
        # there isn't really a .ping() type API endpoint so just connect to IAM and list users
        iam = boto3.client('iam')
        try:
            _ = iam.list_users()
            # just in case we get an iterator, consume it to flush out any error
            collections.deque(_, maxlen=0)
            if log.isEnabledFor(logging.DEBUG):
                log.debug('\n\n%s', _)
                log.debug('\n\n%s', jsonpp(_))
        # pylint: disable=broad-except
        except Exception as _:
            if log.isEnabledFor(logging.DEBUG):
                raise
            else:
                raise CriticalError(_)
        self.msg = 'AWS API credentials OK'


if __name__ == '__main__':
    AWSAPIPing().main()
