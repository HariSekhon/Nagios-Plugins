#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-03-24 22:33:15 +0000 (Thu, 24 Mar 2016)
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

Nagios Plugin to check InfluxDB is available via its Rest API

Sends a simple API ping request and checks the response

Tested on InfluxDB 0.12, 0.13, 1.0, 1.1, 1.2, 1.3, 1.4

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckInfluxDBApiPing(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckInfluxDBApiPing, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'InfluxDB'
        self.default_port = 8086
        self.request_method = 'head'
        self.path = '/ping'
        self.auth = 'optional'
        #self.json = False
        self.msg = 'InfluxDB msg not defined yet'

    def add_options(self):
        super(CheckInfluxDBApiPing, self).add_options()

    def process_options(self):
        super(CheckInfluxDBApiPing, self).process_options()
        # Override default RequestHandler() error checking
        self.request.check_response_code = self.check_response_code

    def parse(self, req):
        # validate X-Influxdb_Version
        if req.status_code == 204:
            self.msg = 'InfluxDB API ping successful'
        else:
            self.critical()
            self.msg = 'InfluxDB API ping failed! Non-204 response code returned'

    def check_response_code(self, req):
        pass


if __name__ == '__main__':
    CheckInfluxDBApiPing().main()
