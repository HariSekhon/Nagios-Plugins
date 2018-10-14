#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-09-06 19:51:47 +0200 (Wed, 06 Sep 2017)
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

Nagios Plugin to check the HDFS space used percentage via NameNode JMX

Written for Hadoop 2.7 as the previously used dfshealth.jsp mechanism in versions <= 2.6
was removed and replaced by AJAX calls to populate tables from JMX info, so this plugin
follows that change.

See adjacent check_hadoop_hdfs_space.pl for older versions of Hadoop <= 2.6

The old program compared used % space between datanodes but this one compares absolute space used as this is how Hadoop
balances and accounts of heterogenous nodes better and calculates the percentage against the most filled datanode

Tested on HDP 2.6.1 and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import re
import sys
import traceback
import humanize
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, isFloat, isInt
    from harisekhon.utils import UnknownError, support_msg_api
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4.1'


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
        self.add_thresholds(default_warning=80, default_critical=90, percent=True)

    def process_options(self):
        super(CheckHadoopHDFSBalance, self).process_options()
        self.validate_thresholds()

    def parse_json(self, json_data):
        log.info('parsing response')
        try:
            bean = json_data['beans'][0]
            space_used_pc = bean['PercentUsed']
            # the way below is more informative
            #assert type(space_used_pc) == float
            if re.search(r'e-\d+$', str(space_used_pc)):
                space_used_pc = 0
            if not isFloat(space_used_pc):
                raise UnknownError("non-float returned for PercentUsed by namenode '{0}:{1}'"\
                                   .format(self.host, self.port))
            if space_used_pc < 0:
                raise UnknownError('space_used_pc {} < 0'.format(space_used_pc))
            stats = {}
            for stat in ('Total', 'TotalBlocks', 'TotalFiles', 'Used'):
                stats[stat] = bean[stat]
                if not isInt(stats[stat]):
                    raise UnknownError("non-integer returned for {0} by namenode '{1}:{2}'"\
                                       .format(stat, self.host, self.port))
                stats[stat] = int(stats[stat])
            self.ok()
            self.msg = 'HDFS space used = {0:.2f}% ({1}/{2})'\
                       .format(space_used_pc, humanize.naturalsize(stats['Used']), humanize.naturalsize(stats['Total']))
            self.check_thresholds(space_used_pc)
            self.msg += ", in {0:d} files spread across {1:d} blocks".format(stats['TotalFiles'], stats['TotalBlocks'])
            self.msg += " | 'HDFS % space used'={0:f}%{1}".format(space_used_pc, self.get_perf_thresholds())
            self.msg += " 'HDFS space used'={0:d}b".format(stats['Used'])
            self.msg += " 'HDFS file count'={0:d}".format(stats['TotalFiles'])
            self.msg += " 'HDFS block count'={0:d}".format(stats['TotalBlocks'])
        except KeyError as _:
            raise UnknownError("failed to parse json returned by NameNode at '{0}:{1}': {2}. {3}"\
                               .format(self.host, self.port, _, support_msg_api()))
        except ValueError as _:
            raise UnknownError("invalid json returned for LiveNodes by Namenode '{0}:{1}': {2}"\
                               .format(self.host, self.port, _))


if __name__ == '__main__':
    CheckHadoopHDFSBalance().main()
