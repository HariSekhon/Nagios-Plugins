#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-01-21 15:37:06 +0000 (Sun, 21 Jan 2018)
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

Nagios Plugin to check the InfluxDB version and optionally build (OSS vs Enterprise) via the InfluxDB Rest API

Tested on InfluxDB 0.12, 0.13, 1.0, 1.1, 1.2, 1.3, 1.4

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
    from harisekhon.utils import UnknownError, validate_regex
    from harisekhon import RestVersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckInfluxDBVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckInfluxDBVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'InfluxDB'
        self.default_port = 8086
        self.path = '/ping'
        self.auth = 'optional'
        #self.json = False
        self.build = None
        self.expected_build = None
        self.ok()

    def add_options(self):
        super(CheckInfluxDBVersion, self).add_options()
        self.add_opt('-b', '--build', help='Expected build information if available (regex)')

    def process_options(self):
        super(CheckInfluxDBVersion, self).process_options()
        self.expected_build = self.get_opt('build')
        if self.expected_build:
            validate_regex(self.expected_build, 'build')
        # Override default RequestHandler() error checking
        self.request.check_response_code = self.check_response_code

    def parse(self, req):
        self.build = None
        # only available in InfluxDB 1.4+
        if 'X-Influxdb-Build' in req.headers:
            self.build = req.headers['X-Influxdb-Build']

        if 'X-Influxdb-Version' not in req.headers:
            raise UnknownError('X-Influxdb-Version header not found in response - not InfluxDB?')
        version = req.headers['X-Influxdb-Version']
        # Enterprise may have versions like 1.6.2-c1.6.2 so remove the suffix
        version = version.split('-')[0]
        return version

    def extra_info(self):
        msg = ''
        if self.build:
            msg = ", build: '{}'".format(self.build)
            if self.expected_build:
                if not re.match(self.expected_build, self.build):
                    self.critical()
                    msg += " (expected '{}')".format(self.expected_build)
        return msg

    def check_response_code(self, req):
        pass


if __name__ == '__main__':
    CheckInfluxDBVersion().main()
