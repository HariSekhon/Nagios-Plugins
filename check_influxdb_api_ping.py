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

Sends a simple API ping request and checks the response code and headers to ensure it is InfluxDB

Uses wait_for_leader=Ns where N is 1 less than the --timeout, with a minimum value of 1 second, this requires 0.9.5+

Tested on InfluxDB 0.12, 0.13, 1.0, 1.1, 1.2, 1.3, 1.4 and InfluxDB Relay

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
    from harisekhon.utils import UnknownError
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4'


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

#    def add_options(self):
#        super(CheckInfluxDBApiPing, self).add_options()

    def process_options(self):
        super(CheckInfluxDBApiPing, self).process_options()
        # Override default RequestHandler() error checking
        self.request.check_response_code = self.check_response_code
        self.path += '?wait_for_leader={}s'.format(max(self.timeout - 1, 1))
        #if self.user and self.password:
        #    self.path += 'u={user}&p={password}'.format(user=self.user, password=self.password)

    def parse(self, req):
        # validate X-Influxdb-Build and X-Influxdb-Version to ensure it is in fact InfluxDB
        #
        # X-Influxdb-Build header is only returned in InfluxDB 1.4+
        #assert 'X-Influxdb-Build' in req.headers
        #if 'X-Influxdb-Build' not in req.headers:
        #    raise UnknownError('X-Influxdb-Build header not found in response')
        #
        #assert 'X-Influxdb-Version' in req.headers
        if 'X-Influxdb-Version' not in req.headers:
            raise UnknownError('X-Influxdb-Version header not found in response - not InfluxDB?')
        if req.status_code == 204:
            self.msg = 'InfluxDB API ping successful, headers validated as InfluxDB'
        else:
            self.critical()
            self.msg = 'InfluxDB API ping failed! Non-204 response code returned'

    def check_response_code(self, req):
        pass


if __name__ == '__main__':
    CheckInfluxDBApiPing().main()
