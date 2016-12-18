#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-09-25 12:21:49 +0100 (Sun, 25 Sep 2016)
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

Nagios Plugin to check the deployed version of an RabbitMQ matches what's expected via the Managementg REST API

This is also used in the accompanying test suite to ensure we're checking the right version of RabbitMQ
for compatibility for all my other RabbitMQ nagios plugins.

Tested on RabbitMQ 3.6.6

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import json
import logging
import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, support_msg_api, jsonpp, \
                                 validate_host, validate_port, validate_user, validate_password
    from harisekhon import VersionNagiosPlugin
    from harisekhon.request_handler import RequestHandler
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckRabbitMQVersion(VersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckRabbitMQVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'RabbitMQ'
        self.host = None
        self.port = None
        self.user = None
        self.password = None
        self.url_path = 'api/overview'

    def add_options(self):
        self.add_hostoption(default_host='localhost', default_port=15672)
        self.add_useroption(default_user='guest', default_password='guest')
        self.add_expected_version_option()

    def process_options(self):
        self.no_args()
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        self.user = self.get_opt('user')
        self.password = self.get_opt('password')
        validate_host(self.host)
        validate_port(self.port)
        validate_user(self.user)
        validate_password(self.password)
        self.process_expected_version_option()

    def get_version(self):
        url = 'http://{host}:{port}/{path}'.format(host=self.host, port=self.port, path=self.url_path)
        req = RequestHandler().get(url, auth=(self.user, self.password))
        try:
            json_data = json.loads(req.content)
            if log.isEnabledFor(logging.DEBUG):
                print(jsonpp(json_data))
                print('=' * 80)
            return json_data['rabbitmq_version']
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', str(_) + support_msg_api())


if __name__ == '__main__':
    CheckRabbitMQVersion().main()
