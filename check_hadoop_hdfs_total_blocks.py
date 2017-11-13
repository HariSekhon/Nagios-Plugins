#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-09-06 14:25:26 +0200 (Wed, 06 Sep 2017)
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

Nagios Plugin to check the number of total blocks in HDFS via NameNode JMX

This is important as it impacts NameNode heap space

Compares the number of total blocks to --warning and --critical thresholds and outputs
graphing data for tracking the block growth over time, which is useful for NameNode capacity planning

Tested on HDP 2.6.1 and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8

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
    from harisekhon.utils import log, isInt
    from harisekhon.utils import UnknownError, support_msg_api
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4'


# pylint: disable=too-few-public-methods
class CheckHadoopHDFSTotalBlocks(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopHDFSTotalBlocks, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Hadoop NameNode', 'Hadoop']
        self.path = '/jmx?qry=Hadoop:service=NameNode,name=NameNodeInfo'
        self.default_port = 50070
        self.json = True
        self.auth = False
        self.msg = 'Message Not Defined'

    def add_options(self):
        super(CheckHadoopHDFSTotalBlocks, self).add_options()
        self.add_thresholds()

    def process_options(self):
        super(CheckHadoopHDFSTotalBlocks, self).process_options()
        self.validate_thresholds()

    def parse_json(self, json_data):
        log.info('parsing response')
        try:
            data = json_data['beans'][0]
            total_blocks = data['TotalBlocks']
            if not isInt(total_blocks):
                raise UnknownError('non-integer returned by NameNode for number of total blocks! {0}'\
                                   .format(support_msg_api()))
            total_blocks = int(total_blocks)
            self.msg = 'HDFS Total Blocks = {0:d}'.format(total_blocks)
            self.check_thresholds(total_blocks)
            self.msg += ' | hdfs_total_blocks={0:d}{1}'.format(total_blocks, self.get_perf_thresholds())
        except KeyError as _:
            raise UnknownError("failed to parse json returned by NameNode at '{0}:{1}': {2}. {3}"\
                               .format(self.host, self.port, _, support_msg_api()))


if __name__ == '__main__':
    CheckHadoopHDFSTotalBlocks().main()
