#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-09-05 16:06:41 +0200 (Tue, 05 Sep 2017)
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

Nagios Plugin to check the HDFS block balance between datanodes via NameNode JMX

Written for Hadoop 2.7 as the previously used dfshealth.jsp mechanism in versions <= 2.6
was removed and replaced by AJAX calls to populate tables from JMX info, so this plugin
follows that change.

See adjacent check_hadoop_datanodes_block_balance.pl for older versions of Hadoop <= 2.6

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


class CheckHadoopDatanodesBlockBalance(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopDatanodesBlockBalance, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Hadoop NameNode', 'Hadoop']
        self.path = '/jmx?qry=Hadoop:service=NameNode,name=NameNodeInfo'
        self.default_port = 50070
        self.json = True
        self.auth = False
        self.msg = 'Message Not Defined'

    def add_options(self):
        super(CheckHadoopDatanodesBlockBalance, self).add_options()
        self.add_thresholds(default_warning=10, default_critical=30, percent=True)

    def process_options(self):
        super(CheckHadoopDatanodesBlockBalance, self).process_options()
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
            max_blocks = 0
            min_blocks = None
            for datanode in live_node_data:
                blocks = live_node_data[datanode]['numBlocks']
                if not isInt(blocks):
                    raise UnknownError('numBlocks {} is not an integer! {}'.format(blocks, support_msg_api()))
                blocks = int(blocks)
                log.info("datanode '%s' has %s blocks", datanode, blocks)
                if blocks > max_blocks:
                    max_blocks = blocks
                if min_blocks is None or blocks < min_blocks:
                    min_blocks = blocks
            log.info("max blocks on a single datanode = %s", max_blocks)
            log.info("min blocks on a single datanode = %s", min_blocks)
            if min_blocks is None:
                raise UnknownError('min_blocks is None')
            divisor = min_blocks
            if min_blocks < 1:
                log.info("min blocks < 1, resetting divisor to 1 (% will be very high)")
                divisor = 1
            block_imbalance = float("{0:.2f}".format((max_blocks - min_blocks) / divisor * 100))
            self.msg = '{0}% block imbalance across {1} datanode{2}'\
                       .format(block_imbalance, num_datanodes, plural(num_datanodes))
            self.ok()
            self.check_thresholds(block_imbalance)
            if self.verbose:
                self.msg += ' (min blocks = {0}, max blocks = {1})'.format(min_blocks, max_blocks)
            self.msg += " | block_imbalance={0}%".format(block_imbalance)
            self.msg += self.get_perf_thresholds()
            self.msg += " num_datanodes={0}".format(num_datanodes)
            self.msg += " min_blocks={0}".format(min_blocks)
            self.msg += " max_blocks={0}".format(max_blocks)
        except KeyError as _:
            raise UnknownError("failed to parse json returned by NameNode at '{0}:{1}': {2}. {3}"\
                               .format(self.host, self.port, _, support_msg_api()))
        except ValueError as _:
            raise UnknownError("invalid json returned for LiveNodes by Namenode '{0}:{1}': {2}"\
                               .format(self.host, self.port, _))


if __name__ == '__main__':
    CheckHadoopDatanodesBlockBalance().main()
