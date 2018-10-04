#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-09-19 09:23:33 +0200 (Mon, 19 Sep 2016)
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

Nagios Plugin to check the last contact time of a given Hadoop datanode via NameNode JMX

If the given datanode is marked as dead this check returns critical regardless of the thresholds, and if marked as
decommissioning but within last contact thresholds then returns warning, or critical if critical threshold is breached.

Written for Hadoop 2.7, replaces older check_hadoop_namenode.pl which used dfshealth.jsp which was removed and replaced
by AJAX calls to populate tables from JMX info, so this plugin follows that change.

Tested on HDP 2.6.1 and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import json
import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, isInt, validate_chars, plural
    from harisekhon.utils import ERRORS, UnknownError, support_msg_api
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.7.1'


class CheckHadoopDatanodeLastContact(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopDatanodeLastContact, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Hadoop NameNode', 'Hadoop']
        self.path = '/jmx?qry=Hadoop:service=NameNode,name=NameNodeInfo'
        self.default_port = 50070
        self.json = True
        self.auth = False
        self.datanode = None
        self.list_nodes = False
        self.msg = 'Message Not Defined'

    def add_options(self):
        super(CheckHadoopDatanodeLastContact, self).add_options()
        self.add_opt('-n', '--node', '--datanode',
                     help='Datanode hostname to check for, must match exactly what the Namenode ' \
                        + 'sees, use --list-nodes to see the list of datanodes')
        self.add_opt('-l', '--list-nodes', action='store_true', help='List datanodes and exit')
        self.add_thresholds(default_warning=30, default_critical=180)

    def process_options(self):
        super(CheckHadoopDatanodeLastContact, self).process_options()
        self.datanode = self.get_opt('node')
        self.list_nodes = self.get_opt('list_nodes')
        if not self.list_nodes:
            validate_chars(self.datanode, 'datanode', 'A-Za-z0-9:_-')
        self.validate_thresholds()

    @staticmethod
    def match_datanode(datanode, item):
        """compare the datanode we expect to the item in nodes list, return True if matching"""
        # it looks like Hadoop 2.7 includes port whereas Hadoop 2.5 / 2.6 doesn't so allow user supplied string
        # to include port to permit enforcing more specific matching, otherwise strip port and try again to
        # match older versions or if user has not supplied port in datanode name
        if datanode == item or datanode == item.split(':')[0]:
            return True
        return False

    def print_nodes(self, live_nodes, dead_nodes, decom_nodes):
        if self.list_nodes:
            print('Live Datanodes:\n')
            if not live_nodes:
                print('<none>')
            for datanode in live_nodes:
                print(datanode)
            print('\nDecommissioning Datanodes:\n')
            if not decom_nodes:
                print('<none>')
            for datanode in decom_nodes:
                print(datanode)
            print('\nDead Datanodes:\n')
            if not dead_nodes:
                print('<none>')
            for datanode in dead_nodes:
                print(datanode)
            sys.exit(ERRORS['UNKNOWN'])

    def parse_json(self, json_data):
        log.info('parsing response')
        try:
            live_nodes_str = json_data['beans'][0]['LiveNodes']
            dead_nodes_str = json_data['beans'][0]['DeadNodes']
            decom_nodes_str = json_data['beans'][0]['DecomNodes']
            live_nodes = json.loads(live_nodes_str)
            dead_nodes = json.loads(dead_nodes_str)
            decom_nodes = json.loads(decom_nodes_str)
            self.print_nodes(live_nodes=live_nodes,
                             dead_nodes=dead_nodes,
                             decom_nodes=decom_nodes)
            last_contact_secs = None
            for item in live_nodes:
                if self.match_datanode(self.datanode, item):
                    last_contact_secs = live_nodes[item]['lastContact']
            # always check decom and dead nodes regardless if last_contact_secs was found in live nodes
            # gives an additional safety check to escalate to warning / critical
            self.msg = ''
            for item in decom_nodes:
                if self.match_datanode(self.datanode, item):
                    last_contact_secs = decom_nodes[item]['lastContact']
                    self.warning()
                    self.msg = 'Decommissioning '
            for item in dead_nodes:
                if self.match_datanode(self.datanode, item):
                    last_contact_secs = dead_nodes[item]['lastContact']
                    self.critical()
                    self.msg = 'Dead '
            if last_contact_secs is None:
                raise UnknownError("datanode '{0}' is not present in any of the live, ".format(self.datanode) + \
                                   "decommissioning or dead node lists!")
            if not isInt(last_contact_secs):
                raise UnknownError("non-integer '{0}' returned for last contact seconds by namenode '{1}:{2}'"\
                                   .format(last_contact_secs, self.host, self.port))
            last_contact_secs = int(last_contact_secs)
            if last_contact_secs < 0:
                raise UnknownError('last_contact_secs {} < 0!'.format(last_contact_secs))
            self.msg += "HDFS datanode '{0}' last contact with namenode was {1} sec{2} ago"\
                       .format(self.datanode, last_contact_secs, plural(last_contact_secs))
            self.check_thresholds(last_contact_secs)
            self.msg += ' | datanode_last_contact_secs={0}'.format(last_contact_secs)
            self.msg += self.get_perf_thresholds()
        except KeyError as _:
            raise UnknownError("failed to parse json returned by NameNode at '{0}:{1}': {2}. {3}"\
                               .format(self.host, self.port, _, support_msg_api()))
        except ValueError as _:
            raise UnknownError("invalid json returned for LiveNodes by Namenode '{0}:{1}': {2}"\
                               .format(self.host, self.port, _))


if __name__ == '__main__':
    CheckHadoopDatanodeLastContact().main()
