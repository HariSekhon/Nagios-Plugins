#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-06-15 18:47:17 +0100 (Fri, 15 Jun 2018)
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

Nagios Plugin to check HDFS Rack Resilience is configured via Ambari API

- checks that more than 1 rack is configured
- checks that no nodes have been added and mistakenly left in /default-rack
  - reports number of nodes left in default rack and in verbose mode lists the nodes
- perfdata of the number of configured racks and number of nodes left in /default-rack

This will report on all nodes, whereas you might only be interested in Datanodes. This is a
limitation of the Ambari API as documented here:

    https://issues.apache.org/jira/browse/AMBARI-24144

See also check_hadoop_hdfs_rack_resilience.py for clusters without Ambari

Tested on Hortonworks HDP 2.6 with Ambari 2.6

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

#import logging
import os
#import re
import sys
#import time
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import validate_chars, plural, ERRORS
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckAmbariClusterHdfsRackResilience(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAmbariClusterHdfsRackResilience, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Ambari'
        self.default_port = 8080
        self.path = '/api/v1/clusters/{cluster}/hosts?fields=Hosts/rack_info'
        self.json = True
        self.list = False
        self.msg = 'Ambari message not defined yet'

    def add_options(self):
        super(CheckAmbariClusterHdfsRackResilience, self).add_options()
        self.add_opt('-C', '--cluster', default=os.getenv('AMBARI_CLUSTER'),
                     help='Ambari Cluster name (eg. Sandbox, $AMBARI_CLUSTER)')
        self.add_opt('-l', '--list', action='store_true', help='List clusters and exit')

    def process_options(self):
        super(CheckAmbariClusterHdfsRackResilience, self).process_options()
        self.no_args()
        cluster = self.get_opt('cluster')
        validate_chars(cluster, 'cluster', 'A-Za-z0-9-_')
        self.path = self.path.format(cluster=cluster)
        # RestNagiosPlugin auto sets 'Accept'='application/json' but this breaks Ambari, fixed in pylib now
        #self.headers = {}
        if self.get_opt('list'):
            self.path = '/api/v1/clusters'
            self.list = True

    def parse_json(self, json_data):
        if self.list:
            print('Ambari Clusters:\n')
            for _ in json_data['items']:
                print(_['Clusters']['cluster_name'])
            sys.exit(ERRORS['UNKNOWN'])
        racks = {}
        for host in json_data['items']:
            host_name = host['Hosts']['host_name']
            rack = host['Hosts']['rack_info']
            if rack not in racks:
                racks[rack] = []
            racks[rack].append(host_name)
        num_racks = len(racks)
        self.msg = '{} rack{} configured'.format(num_racks, plural(num_racks))
        if num_racks < 2:
            self.warning()
            self.msg += ' (no rack resilience!)'
        default_rack = '/default-rack'
        num_nodes_left_in_default_rack = 0
        if default_rack in racks:
            self.warning()
            num_nodes_left_in_default_rack = len(racks[default_rack])
            msg = "{num} node{plural} left in '{default_rack}'!"\
                  .format(num=num_nodes_left_in_default_rack,
                          plural=plural(num_nodes_left_in_default_rack),
                          default_rack=default_rack)
            if self.verbose:
                msg += ' [{}]'.format(', '.join(racks[default_rack]))
            self.msg = msg + ' - ' + self.msg
        self.msg += ' | hdfs_racks={};2 nodes_in_default_rack={};0'\
                    .format(num_racks, num_nodes_left_in_default_rack)


if __name__ == '__main__':
    CheckAmbariClusterHdfsRackResilience().main()
