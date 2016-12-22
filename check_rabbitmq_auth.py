#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-20 17:30:59 +0000 (Tue, 20 Dec 2016)
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

Nagios Plugin to check authentication to the RabbitMQ Management REST API

Requires the management plugin to be loaded.

Validates the user name returned by the API matches the user that was sent to authenticate as
and also applies an optional --tags regex to check the permissions the user has been assigned.

Can use this as a check dependency for all other RabbitMQ management API checks.

User account given must have minimum of 'management' user tag assigned.

Tested on RabbitMQ 3.4.4, 3.5.7, 3.6.6

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import re
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import validate_regex, CriticalError
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.1'


class CheckRabbitMQAuth(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckRabbitMQAuth, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'RabbitMQ'
        self.default_port = 15672
        self.default_user = 'guest'
        self.default_password = 'guest'
        self.expected_tag = None
        self.path = 'api/whoami'
        self.json = True
        self.msg = 'msg not defined yet'

    def add_options(self):
        super(CheckRabbitMQAuth, self).add_options()
        self.add_opt('-T', '--tag', metavar='regex',
                     help='Tag regex of permissions to expect to be applied to authenticated user ' + \
                          '(eg. administrator, management, policymaker, monitoring' + \
                          '. Optional, anchored regex)')

    def process_options(self):
        super(CheckRabbitMQAuth, self).process_options()
        self.expected_tag = self.get_opt('tag')
        if self.expected_tag:
            validate_regex(self.expected_tag, 'expected tag')

    def parse_json(self, json_data):
        returned_user = json_data['name']
        tags = json_data['tags']
        if returned_user != self.user:
            raise CriticalError("RabbitMQ user '{user}' was authenticated ".format(user=self.user) + \
                                "but the API returned user name '{returned_user}'!".format(returned_user=returned_user))
        self.msg = "RabbitMQ user '{returned_user}' tags '{tags}'".format(returned_user=returned_user, tags=tags)
        if self.expected_tag and not re.match('^' + self.expected_tag + '$', tags):
            self.msg += " (expected '{0}')".format(self.expected_tag)
            self.critical()


if __name__ == '__main__':
    CheckRabbitMQAuth().main()
