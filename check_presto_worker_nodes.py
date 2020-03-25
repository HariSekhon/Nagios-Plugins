#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-09-22 16:55:57 +0200 (Fri, 22 Sep 2017)
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

Nagios Plugin to check the number of Presto SQL worker nodes via the Coordinator API

Coordinator nodes do not show up in the worker node count

Will get a '404 Not Found' if you try to run it against a Presto Worker as this information
is only available via the Presto Coordinator API

Testing shows that a work will still be shown in this number even just after it's started failing,
must use adjacent plugins to detect worker failure via response time lag to coordinator or recent failures
/ recent failure ratio increases

See also:

    - check_presto_worker_node.py (includes response lag / recent failures / failure ratio for a specific worker node)
    - check_presto_worker_nodes_failed.py
    - check_presto_worker_nodes_recent_failure_ratio.py
    - check_presto_worker_nodes_recent_failures.py
    - check_presto_worker_nodes_response_lag.py

Thresholds apply to the minimum number of Presto worker nodes to expect

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
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import UnknownError, support_msg_api, isList
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckPrestoWorkerNodes(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPrestoWorkerNodes, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Presto Coordinator', 'Presto']
        self.default_port = 8080
        self.auth = False
        self.json = True
        self.path = '/v1/node'
        self.msg = 'Presto msg not defined'

    def add_options(self):
        super(CheckPrestoWorkerNodes, self).add_options()
        self.add_thresholds(default_critical=1)

    def process_options(self):
        super(CheckPrestoWorkerNodes, self).process_options()
        self.validate_thresholds(simple='lower')

    def parse_json(self, json_data):
        if not isList(json_data):
            raise UnknownError('non-list returned by Presto for nodes. {0}'.format(support_msg_api()))
        num_worker_nodes = len(json_data)
        self.msg = 'Presto SQL worker nodes = {0}'.format(num_worker_nodes)
        self.check_thresholds(num_worker_nodes)
        self.msg += ' | num_worker_nodes={0}{1}'.format(num_worker_nodes, self.get_perf_thresholds('lower'))


if __name__ == '__main__':
    CheckPrestoWorkerNodes().main()
