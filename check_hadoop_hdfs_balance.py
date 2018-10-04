#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-09-06 19:51:35 +0200 (Wed, 06 Sep 2017)
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

Nagios Plugin to check the HDFS data balance between datanodes via NameNode JMX

Written for Hadoop 2.7 as the previously used dfshealth.jsp mechanism in versions <= 2.6
was removed and replaced by AJAX calls to populate tables from JMX info, so this plugin
follows that change.

See adjacent check_hadoop_balance.pl for older versions of Hadoop <= 2.6

The old program compared used % space between datanodes but this one compares absolute space used as this is how Hadoop
balances and accounts of heterogenous nodes better and calculates the percentage against the most filled datanode

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
    from harisekhon.utils import log, plural, isInt
    from harisekhon.utils import CriticalError, UnknownError, support_msg_api
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.5.1'


class CheckHadoopHDFSBalance(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopHDFSBalance, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Hadoop NameNode', 'Hadoop']
        self.path = '/jmx?qry=Hadoop:service=NameNode,name=NameNodeInfo'
        self.default_port = 50070
        self.json = True
        self.auth = False
        self.msg = 'Message Not Defined'

    def add_options(self):
        super(CheckHadoopHDFSBalance, self).add_options()
        self.add_thresholds(default_warning=10, default_critical=30, percent=True)

    def process_options(self):
        super(CheckHadoopHDFSBalance, self).process_options()
        self.validate_thresholds()

    def parse_json(self, json_data):
        log.info('parsing response')
        try:
            live_nodes = json_data['beans'][0]['LiveNodes']
            live_node_data = json.loads(live_nodes)
            num_datanodes = len(live_node_data)
            if num_datanodes < 1:
                raise CriticalError("no live datanodes returned by JMX API from namenode '{0}:{1}'"\
                                    .format(self.host, self.port))
            min_space = None
            max_space = 0
            for datanode in live_node_data:
                used_space = live_node_data[datanode]['usedSpace']
                if not isInt(used_space):
                    raise UnknownError('usedSpace {} is not an integer! {}'.format(used_space, support_msg_api()))
                used_space = int(used_space)
                log.info("datanode '%s' used space = %s", datanode, used_space)
                if min_space is None or used_space < min_space:
                    min_space = used_space
                if used_space > max_space:
                    max_space = used_space
            divisor = max_space
            if divisor < 1:
                log.info('min used space < 1, resetting divisor to 1 (% will likely be very high)')
                divisor = 1
            if max_space < min_space:
                raise UnknownError('max_space < min_space')
            largest_imbalance_pc = float('{0:.2f}'.format(((max_space - min_space) / divisor) * 100))
            if largest_imbalance_pc < 0:
                raise UnknownError('largest_imbalance_pc < 0')
            self.ok()
            self.msg = '{0}% HDFS imbalance on space used'.format(largest_imbalance_pc)
            self.check_thresholds(largest_imbalance_pc)
            self.msg += ' across {0:d} datanode{1}'.format(num_datanodes, plural(num_datanodes))
            if self.verbose:
                self.msg += ', min used space = {0}, max used space = {1}'.format(min_space, max_space)
            if self.verbose and (self.is_warning() or self.is_critical()):
                self.msg += ' [imbalanced nodes: '
                for datanode in live_node_data:
                    used_space = live_node_data[datanode]['usedSpace']
                    if (used_space / max_space * 100) > self.thresholds['warning']['upper']:
                        self.msg += '{0}({1:.2f%}),'.format(datanode, used_space)
                self.msg = self.msg.rstrip(',') + ']'
            self.msg += " | 'HDFS imbalance on space used %'={0}".format(largest_imbalance_pc)
            self.msg += self.get_perf_thresholds()
            self.msg += " num_datanodes={0}".format(num_datanodes)
            self.msg += " min_used_space={0}".format(min_space)
            self.msg += " max_used_space={0}".format(max_space)
        except KeyError as _:
            raise UnknownError("failed to parse json returned by NameNode at '{0}:{1}': {2}. {3}"\
                               .format(self.host, self.port, _, support_msg_api()))
        #except ValueError as _:
        #    raise UnknownError("invalid json returned for LiveNodes by Namenode '{0}:{1}': {2}"\
        #                       .format(self.host, self.port, _))


if __name__ == '__main__':
    CheckHadoopHDFSBalance().main()
