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

Tested on HDP 2.6.1 and Apache Hadoop 2.7.3

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import json
import os
import sys
import time
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, plural, isInt
    from harisekhon.utils import UnknownError, support_msg_api
    from harisekhon.utils import validate_host, validate_port
    from harisekhon import NagiosPlugin
    from harisekhon import RequestHandler
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckHadoopHdfsDatanodesBlockBalance(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopHdfsDatanodesBlockBalance, self).__init__()
        # Python 3.x
        # super().__init__()
        self.host = None
        self.port = None
        self.msg = 'Message Not Defined'
        self.protocol = 'http'
        self.request = RequestHandler()

    def add_options(self):
        self.add_hostoption(name='Hadoop NameNode', default_host='localhost', default_port=50070)
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')
        self.add_thresholds(default_warning=10, default_critical=30, percent=True)

    def process_options(self):
        self.no_args()
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        validate_host(self.host)
        validate_port(self.port)
        if self.get_opt('ssl'):
            self.protocol = 'https'
        self.validate_thresholds()

    def run(self):
        url = '{protocol}://{host}:{port}/jmx?qry=Hadoop:service=NameNode,name=NameNodeInfo'\
              .format(host=self.host, port=self.port, protocol=self.protocol)
        start_time = time.time()
        req = self.request.get(url)
        query_time = time.time() - start_time
        self.check_block_balance(req)
        self.msg += ' | query_time={0:f}s'.format(query_time)

    def check_block_balance(self, req):
        log.info('parsing response')
        try:
            json_data = json.loads(req.content)
            live_nodes = json_data['beans'][0]['LiveNodes']
            live_node_data = json.loads(live_nodes)
            num_datanodes = len(live_node_data)
            if num_datanodes < 1:
                raise UnknownError("no datanodes returned by JMX API from namenode '{0}:{1}'".format(self.host, self.port))
            max_blocks = 0
            min_blocks = None
            for datanode in live_node_data:
                blocks = live_node_data[datanode]['numBlocks']
                if not isInt(blocks):
                    raise UnknownError('numBlocks is not an integer! {0}'.format(support_msg_api()))
                blocks = int(blocks)
                log.info("datanode %s has %s blocks", datanode, blocks)
                if blocks > max_blocks:
                    max_blocks = blocks
                if min_blocks is None or blocks < min_blocks:
                    min_blocks = blocks
            log.info("max blocks on a single datanode = %s", max_blocks)
            log.info("min blocks on a single datanode = %s", min_blocks)
            assert min_blocks is not None
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
            self.msg += " max_blocks={0}".format(max_blocks)
            self.msg += " min_blocks={0}".format(min_blocks)
        except KeyError as _:
            raise UnknownError("failed to parse json returned by NameNode at '{0}:{1}': {2}. {3}"\
                               .format(self.host, self.port, _, support_msg_api()))
        except ValueError as _:
            raise UnknownError("invalid json returned by Namenode '{0}:{1}': {2}".format(self.host, self.port, _))


if __name__ == '__main__':
    CheckHadoopHdfsDatanodesBlockBalance().main()
