#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-09-22 15:45:06 +0200 (Fri, 22 Sep 2017)
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

Nagios Plugin to check the configured environment of a Presto SQL node via the API

Works on both Presto Coordinator and Worker APIs

Tested on:

- Presto Facebook versions:               0.152, 0.157, 0.167, 0.179, 0.185, 0.186, 0.187, 0.188, 0.189
- Presto Teradata distribution versions:  0.152, 0.157, 0.167, 0.179
- back tested against all Facebook Presto releases 0.69, 0.71 - 0.189
  (see Presto docker images on DockerHub at https://hub.docker.com/u/harisekhon)

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
__version__ = '0.1'


class CheckPrestoEnvironment(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPrestoEnvironment, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Presto'
        self.default_port = 8080
        self.auth = False
        self.json = True
        self.path = '/v1/service/presto/general'
        self.msg = 'Presto SQL node environment = '
        self.expected = None

    def add_options(self):
        super(CheckPrestoEnvironment, self).add_options()
        self.add_opt('-e', '--expected', help='Expected environment setting (regex)')

    def process_options(self):
        super(CheckPrestoEnvironment, self).process_options()
        self.expected = self.get_opt('expected')
        if self.expected:
            validate_regex(self.expected, 'expected environment')

    def parse_json(self, json_data):
        environment = json_data['environment']
        self.msg += "'{0}'".format(environment)
        if self.expected and not re.match(self.expected + '$', environment):
            self.critical()
            self.msg += " (expected '{0}')".format(self.expected)


if __name__ == '__main__':
    CheckPrestoEnvironment().main()
