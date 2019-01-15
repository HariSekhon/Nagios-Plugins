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

Nagios Plugin to check a specific Apache Drill node is detected among online cluster nodes
via the Rest API of any given Drillbit in the cluster

This will show if the Drillbit is registered properly in the cluster

This is an additional layer because the Drill status API is not always accurate (see DRILL-5990 and DRILL-6406)

Recommend to combine this with the Drill HAProxy config from the haproxy/ directory
to run this via any node in the cluster (or combine with find_active_apache_drill.py, see README)

Tested on Apache Drill 1.10, 1.11, 1.12, 1.13, 1.14, 1.15

(API endpoint is not available in Apache Drill versions < 1.10, but this
plugin works best in Apache Drill 1.12+ which has a state field to verify for additional assurance)

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
    from harisekhon.utils import ERRORS, validate_host
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckApacheDrillClusterNode(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckApacheDrillClusterNode, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Apache Drill'
        self.path = '/cluster.json'
        self.default_port = 8047
        self.json = True
        self.auth = False
        self.node = None
        self.list_nodes = False
        self.msg = 'Apache Drill message not defined'

    def add_options(self):
        super(CheckApacheDrillClusterNode, self).add_options()
        self.add_opt('-n', '--node', help='Node to check is seen in cluster (hostname or IP as seen in --list)')
        self.add_opt('-l', '--list', action='store_true', help='List nodes and exit')

    def process_options(self):
        super(CheckApacheDrillClusterNode, self).process_options()
        self.node = self.get_opt('node')
        self.list_nodes = self.get_opt('list')
        if not self.list_nodes:
            validate_host(self.node, 'node')

    @staticmethod
    def list_drillbits(drillbits):
        print('Apache Drill nodes:\n')
        print('=' * 80)
        format_string = '{:30}\t{:10}\t{:10}\t{}'
        print(format_string.format('Address', 'State', 'Version', 'Version Match'))
        print('=' * 80)
        for drillbit in drillbits:
            address = drillbit['address']
            if 'state' in drillbit:
                state = drillbit['state']
            else:
                state = 'N/A'
            version = drillbit['version']
            version_match = drillbit['versionMatch']
            print(format_string.format(address, state, version, version_match))
        sys.exit(ERRORS['UNKNOWN'])

    def parse_json(self, json_data):
        drillbits = json_data['drillbits']
        if self.list_nodes:
            self.list_drillbits(drillbits)
        found = 0
        for drillbit in drillbits:
            address = drillbit['address']
            if address == self.node:
                found = 1
                if 'state' in drillbit:
                    state = drillbit['state']
                else:
                    state = 'N/A'
                version = drillbit['version']
                version_match = drillbit['versionMatch']
                break
        self.msg = "Apache Drill cluster node '{}' ".format(self.node)
        self.ok()
        if not found:
            self.critical()
            self.msg += 'not found (did you specify the correct node address? See --list)'
        else:
            self.msg += "state = '{}'".format(state)

            # state field is currently undocumented but STARTUP has been observed, see:
            #
            # https://issues.apache.org/jira/browse/DRILL-6408
            #
            # States can be found here:
            #
            # https://github.com/apache/drill/blob/master/exec/java-exec/src/main/java/org/apache/drill/exec/server/DrillbitStateManager.java#L25  pylint: disable=line-too-long
            #
            if state == 'STARTUP':
                self.warning()
            elif state not in ('ONLINE', 'N/A'):
                self.msg += ' (!)'
                self.critical()
            self.msg += ", version = '{}', version match = {}".format(version, version_match)
            if not version_match:
                self.warning()
                self.msg += ' (!)'


if __name__ == '__main__':
    CheckApacheDrillClusterNode().main()
