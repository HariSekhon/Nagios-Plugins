#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-10-12 15:18:19 +0200 (Thu, 12 Oct 2017)
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

Nagios Plugin to check the seconds since last response for all Presto SQL worker nodes via the Coordinator API

Thresholds apply to the permitted number of worker nodes exceeding --max-age

Tests show workers usually respond to coordinator node every second even when there are no queries issued

Will raise Warning if no presto worker nodes are found

Will get a '404 Not Found' if you try to run it against a Presto Worker as this information
is only available via the Presto Coordinator API

In verbose mode outputs the list of worker nodes with last responses > max age

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

from datetime import datetime
import os
import re
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, UnknownError, support_msg_api, isList, validate_int
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckPrestoWorkersResponseLag(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPrestoWorkersResponseLag, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Presto Coordinator', 'Presto']
        self.default_port = 8080
        self.auth = False
        self.json = True
        self.path = '/v1/node'
        self.max_age = None
        self.msg = 'Presto msg not defined'

    def add_options(self):
        super(CheckPrestoWorkersResponseLag, self).add_options()
        self.add_opt('-a', '--max-age', metavar='secs', default=10,
                     help='Max age in secs since workers last response to coordinator (default: 10)')
        self.add_thresholds(default_warning=0, default_critical=1)

    def process_options(self):
        super(CheckPrestoWorkersResponseLag, self).process_options()
        self.max_age = self.get_opt('max_age')
        validate_int(self.max_age, 'max age', 0, 3600)
        self.max_age = int(self.max_age)
        self.validate_thresholds()

    def parse_json(self, json_data):
        if not isList(json_data):
            raise UnknownError('non-list returned by Presto for nodes. {0}'.format(support_msg_api()))
        nodes_lagging = []
        max_lag = 0
        re_protocol = re.compile('^https?://')
        num_nodes = len(json_data)
        for node_item in json_data:
            last_response_time = node_item['lastResponseTime']
            last_response_datetime = datetime.strptime(last_response_time, '%Y-%m-%dT%H:%M:%S.%fZ')
            timedelta = datetime.utcnow() - last_response_datetime
            response_age = int(timedelta.total_seconds())
            if response_age > max_lag:
                max_lag = response_age
            if response_age > self.max_age:
                uri = node_item['uri']
                uri = re_protocol.sub('', uri)
                nodes_lagging += [uri]
                log.info("node '%s' last response age %d secs > max age %s secs",
                         node_item['uri'], response_age, self.max_age)
            else:
                log.info("node '%s' last response age %d secs", node_item['uri'], response_age)
        num_nodes_lagging = len(nodes_lagging)
        self.msg = 'Presto SQL - worker nodes with response timestamps older than {0:d} secs = {1:d}'\
                   .format(self.max_age, num_nodes_lagging)
        self.check_thresholds(num_nodes_lagging)
        self.msg += ' out of {0:d} nodes'.format(num_nodes)
        if num_nodes < 1:
            self.warning()
            self.msg += ' (< 1 worker found)'
        self.msg += ', current max response age = {0:.2f} secs'.format(max_lag)
        if self.verbose and nodes_lagging:
            self.msg += ' [{0}]'.format(', '.join(nodes_lagging))
        self.msg += ' | num_nodes_lagging={0}{1} max_response_age={2:.2f}s'\
                    .format(num_nodes_lagging, self.get_perf_thresholds(), max_lag)


if __name__ == '__main__':
    CheckPrestoWorkersResponseLag().main()
