#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-05-04 18:34:23 +0100 (Fri, 04 May 2018)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback # pylint: disable=line-too-long
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check the number of Apache Drill cluster nodes offline via the Rest API of any given node

Thresholds apply to the number of offline drillbits

Recommend to combine this with the Drill HAProxy config from the haproxy/ directory
to run this via any node in the cluster (or combine with find_active_apache_drill.py, see README)

Tested on Apache Drill 1.12, 1.13, 1.14, 1.15

(API endpoint is not available in Apache Drill versions < 1.10 and
the state field isn't available before Apache Drill 1.12 so this plugin can only be used on Apache Drill 1.12+)

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import RestNagiosPlugin
    from harisekhon.utils import log, UnknownError
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckApacheDrillClusterNodesOffline(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckApacheDrillClusterNodesOffline, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Apache Drill'
        self.path = '/cluster.json'
        self.default_port = 8047
        self.json = True
        self.auth = False
        self.msg = 'Apache Drill message not defined'

    def add_options(self):
        super(CheckApacheDrillClusterNodesOffline, self).add_options()
        self.add_thresholds(default_warning=0)

    def process_options(self):
        super(CheckApacheDrillClusterNodesOffline, self).process_options()
        self.validate_thresholds(simple='upper', positive=True, optional=True)

    def parse_json(self, json_data):
        drillbits = json_data['drillbits']
        online_nodes = 0
        for drillbit in drillbits:
            if 'state' not in drillbit:
                raise UnknownError('state field not found, is this Apache Drill < 1.12?')
            if drillbit['state'] == 'ONLINE':
                online_nodes += 1
            else:
                log.warning("node '%s' state = '{}'", drillbit['address'])
        total_nodes = len(drillbits)
        offline_nodes = total_nodes - online_nodes
        self.msg = 'Apache Drill cluster: drillbits offline = {}'.format(offline_nodes)
        self.check_thresholds(offline_nodes)
        self.msg += ', drillbits online = {}'.format(online_nodes)
        self.msg += ', total drillbits = {}'.format(total_nodes)
        self.msg += ' | drillbits_offline={}{} drillbits_online={} drillbits_total={}'\
                    .format(offline_nodes, self.get_perf_thresholds(), online_nodes, total_nodes)


if __name__ == '__main__':
    CheckApacheDrillClusterNodesOffline().main()
