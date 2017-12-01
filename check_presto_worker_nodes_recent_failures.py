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

Nagios Plugin to Presto SQL worker nodes for recent failures via the Coordinator API

Thresholds apply to the permitted number of worker nodes with recent failures exceeding --max-failures

In verbose mode outputs the list of worker nodes with recent failures > max failure threshold

Will raise Warning if no presto worker nodes are found

Will get a '404 Not Found' if you try to run it against a Presto Worker as this information
is only available via the Presto Coordinator API

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
    from harisekhon.utils import log, UnknownError, support_msg_api, isList, validate_float, isFloat
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3.1'


class CheckPrestoWorkersFailures(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPrestoWorkersFailures, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Presto Coordinator', 'Presto']
        self.default_port = 8080
        self.auth = False
        self.json = True
        self.path = '/v1/node'
        self.max_failures = None
        self.msg = 'Presto msg not defined'

    def add_options(self):
        super(CheckPrestoWorkersFailures, self).add_options()
        self.add_opt('-f', '--max-failures', metavar='0', default=0,
                     help='Max failures to tolerate on each node (default: 0)')
        self.add_thresholds(default_warning=0, default_critical=1)

    def process_options(self):
        super(CheckPrestoWorkersFailures, self).process_options()
        self.max_failures = self.get_opt('max_failures')
        validate_float(self.max_failures, 'max recent failures', 0, 1000)
        self.max_failures = float('{0:.2f}'.format(float(self.max_failures)))
        self.validate_thresholds()

    def parse_json(self, json_data):
        if not isList(json_data):
            raise UnknownError('non-list returned by Presto for nodes. {0}'.format(support_msg_api()))
        nodes_failing = []
        max_failures = 0.0
        re_protocol = re.compile('^https?://')
        num_nodes = len(json_data)
        for node_item in json_data:
            recent_failures = node_item['recentFailures']
            if not isFloat(recent_failures):
                raise UnknownError('recentFailures is not a float! {0}'.format(support_msg_api()))
            recent_failures = float('{0:.2f}'.format(recent_failures))
            if recent_failures < 0:
                raise UnknownError('recentFailures < 0 ?!!! {0}'.format(support_msg_api()))
            if recent_failures > max_failures:
                max_failures = recent_failures
            if recent_failures > self.max_failures:
                uri = node_item['uri']
                uri = re_protocol.sub('', uri)
                nodes_failing += [uri]
                log.info("node '%s' recent failures %f > max failures %f",
                         node_item['uri'], recent_failures, self.max_failures)
            elif recent_failures:
                log.info("node '%s' recent failures %f, but less than max failures threshold of %f",
                         node_item['uri'], recent_failures, self.max_failures)
        num_nodes_failing = len(nodes_failing)
        self.msg = 'Presto SQL - worker nodes with recent failures > {0:.2f} = {1:d}'\
                   .format(self.max_failures, num_nodes_failing)
        if num_nodes < 1:
            self.warning()
            self.msg += ' (< 1 worker found)'
        self.check_thresholds(num_nodes_failing)
        self.msg += ' out of {0:d} nodes'.format(num_nodes)
        self.msg += ', max recent failures per node = {0:.2f}'.format(max_failures)
        if self.verbose and nodes_failing:
            self.msg += ' [{0}]'.format(','.join(nodes_failing))
        self.msg += ' | num_nodes_failing={0}{1} max_recent_failures={2:.2f}'\
                    .format(num_nodes_failing, self.get_perf_thresholds(), max_failures)


if __name__ == '__main__':
    CheckPrestoWorkersFailures().main()
