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

Nagios Plugin to check the recent failure ratio for all Presto SQL worker nodes via the Coordinator API

Thresholds apply to the permitted number of worker nodes with recent failure ratios exceeding --max-ratio

In verbose mode outputs the list of nodes with recent failure ratios > max ratio threshold

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
__version__ = '0.3'


class CheckPrestoWorkersFailureRatio(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPrestoWorkersFailureRatio, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Presto Coordinator', 'Presto']
        self.default_port = 8080
        self.auth = False
        self.json = True
        self.path = '/v1/node'
        self.max_ratio = None
        self.msg = 'Presto msg not defined'

    def add_options(self):
        super(CheckPrestoWorkersFailureRatio, self).add_options()
        self.add_opt('-r', '--max-ratio', metavar='0.1', default=0.1,
                     help='Max failure ratio on each node (default: 0.1)')
        self.add_thresholds(default_warning=0, default_critical=1)

    def process_options(self):
        super(CheckPrestoWorkersFailureRatio, self).process_options()
        self.max_ratio = self.get_opt('max_ratio')
        validate_float(self.max_ratio, 'max recent failure ratio', 0, 1.0)
        self.max_ratio = float('{0:.2f}'.format(float(self.max_ratio)))
        self.validate_thresholds()

    def parse_json(self, json_data):
        if not isList(json_data):
            raise UnknownError('non-list returned by Presto for nodes. {0}'.format(support_msg_api()))
        nodes_failing = []
        max_ratio = 0.0
        re_protocol = re.compile('^https?://')
        num_nodes = len(json_data)
        for node_item in json_data:
            recent_failure_ratio = node_item['recentFailureRatio']
            if not isFloat(recent_failure_ratio):
                raise UnknownError('recentFailureRatio is not a float! {0}'.format(support_msg_api()))
            recent_failure_ratio = float('{0:.2f}'.format(recent_failure_ratio))
            if recent_failure_ratio < 0:
                raise UnknownError('recentFailureRatio < 0 ?!!! {0}'.format(support_msg_api()))
            if recent_failure_ratio > 1:
                raise UnknownError('recentFailureRatio > 1 ?!!! {0}'.format(support_msg_api()))
            if recent_failure_ratio > max_ratio:
                max_ratio = recent_failure_ratio
            if recent_failure_ratio > self.max_ratio:
                uri = node_item['uri']
                uri = re_protocol.sub('', uri)
                nodes_failing += [uri]
                log.info("node '%s' recent failure ratio %f > max ratio %f",
                         node_item['uri'], recent_failure_ratio, self.max_ratio)
            elif recent_failure_ratio:
                log.info("node '%s' recent failures ratio %f, but less than max ratio threshold of %f",
                         node_item['uri'], recent_failure_ratio, self.max_ratio)
        num_nodes_failing = len(nodes_failing)
        self.msg = 'Presto SQL - worker nodes with recent failure ratio > {0:.2f} = {1:d}'\
                   .format(self.max_ratio, num_nodes_failing)
        self.check_thresholds(num_nodes_failing)
        self.msg += ' out of {0:d} nodes'.format(num_nodes)
        if num_nodes < 1:
            self.warning()
            self.msg += ' (< 1 worker found)'
        self.msg += ', max recent failure ratio = {0:.2f}'.format(max_ratio)
        if self.verbose and nodes_failing:
            self.msg += ' [{0}]'.format(','.join(nodes_failing))
        self.msg += ' | num_nodes_failing={0}{1} max_ratio={2:.2f}'\
                    .format(num_nodes_failing, self.get_perf_thresholds(), max_ratio)


if __name__ == '__main__':
    CheckPrestoWorkersFailureRatio().main()
