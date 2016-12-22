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

Nagios Plugin to check the RabbitMQ cluster name via the RabbitMQ Management REST API

Requires the management plugin to be loaded.

Useful to ensure RabbitMQ brokers are in the same expected cluster.

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
    from harisekhon.utils import validate_regex
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.1'


class CheckRabbitMQClusterName(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckRabbitMQClusterName, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'RabbitMQ'
        self.default_port = 15672
        self.default_user = 'guest'
        self.default_password = 'guest'
        self.expected = None
        self.path = 'api/cluster-name'
        self.json = True
        self.msg = 'msg not defined yet'

    def add_options(self):
        super(CheckRabbitMQClusterName, self).add_options()
        self.add_opt('-e', '--expected', metavar='regex',
                     help='Cluster name regex to expect (anchored, optional)')

    def process_options(self):
        super(CheckRabbitMQClusterName, self).process_options()
        self.expected = self.get_opt('expected')
        if self.expected:
            validate_regex(self.expected, 'expected')

    def parse_json(self, json_data):
        cluster_name = json_data['name']
        self.msg = "RabbitMQ cluster name = '{0}'".format(cluster_name)
        if self.expected and not re.match('^' + self.expected + '$', cluster_name):
            self.msg += " (expected '{0}')".format(self.expected)
            self.critical()


if __name__ == '__main__':
    CheckRabbitMQClusterName().main()
