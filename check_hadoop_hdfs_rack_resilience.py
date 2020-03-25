#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-06-15 18:50:36 +0100 (Fri, 15 Jun 2018)
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

Nagios Plugin to check Hadoop HDFS rack resilience is properly configured by parsing the rack information
from the 'hdfs dfsadmin' command

The 'hdfs' command must be in the $PATH and you should execute this program as the 'hdfs' superuser

See also check_ambari_cluster_hdfs_rack_resilience.py - it's a cleaner way of checking this via the Ambari API
on Hortonworks HDP clusters

Tested on Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import re
import subprocess
import sys
import time
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log
    from harisekhon.utils import CriticalError, UnknownError, support_msg
    from harisekhon.utils import ip_regex, host_regex, plural
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckHadoopHdfsRackResilience(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopHdfsRackResilience, self).__init__()
        # Python 3.x
        # super().__init__()
        self.query_time = None
        self.msg = 'HDFS Rack Resilience Msg not defined yet'

    def add_options(self):
        super(CheckHadoopHdfsRackResilience, self).add_options()

    def process_options(self):
        super(CheckHadoopHdfsRackResilience, self).process_options()
        #self.no_args()

    def get_rack_info(self):
        rack_regex = re.compile(r'^Rack:\s+(.+?)\s*$')
        node_regex = re.compile(r'^\s+({ip})(?::\d+)?\s+\(({host})\)\s*$'.format(ip=ip_regex, host=host_regex))
        #node_regex = re.compile(r'^\s+(.*?).*\s+\((.*?)\)\s*'.format(ip=ip_regex))
        start = time.time()
        cmd = 'hdfs dfsadmin -printTopology'
        log.debug('cmd: ' + cmd)
        proc = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (stdout, _) = proc.communicate()
        self.query_time = time.time() - start
        log.debug('stdout: ' + str(stdout))
        returncode = proc.wait()
        log.debug('returncode: ' + str(returncode))
        if returncode != 0 or (stdout is not None and 'Error' in stdout):
            raise CriticalError('hdfs command returncode: {0}, output: {1}'.format(returncode, stdout))
        lines = str(stdout).split('\n')

        racks = {}
        rack = None
        for line in lines:
            match = rack_regex.match(line)
            if match:
                rack = match.group(1)
                log.info('found rack: %s', rack)
                continue
            # ignore early warning lines sometimes output by JVM
            # only continue from point where we find at least first Rack definition
            if not rack:
                continue
            match = node_regex.match(line)
            if match:
                #ip = match.group(1)
                host = match.group(2)
                log.info('found host: %s', host)
                # already checked above
                #if not rack:
                #    raise UnknownError('node regex matched before rack was detected!! {}'.format(support_msg()))
                if rack not in racks:
                    racks[rack] = []
                racks[rack].append(host)
            elif not line:
                continue
            else:
                raise UnknownError('parsing error. {}'.format(support_msg()))
        if not rack:
            raise UnknownError('no rack information found - parse error. {}'.format(support_msg()))
        return racks

    def run(self):
        racks = self.get_rack_info()
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
        self.msg += ' | hdfs_racks={};2 nodes_in_default_rack={};0 query_time={:.2f}s'\
                    .format(num_racks, num_nodes_left_in_default_rack, self.query_time)


if __name__ == '__main__':
    CheckHadoopHdfsRackResilience().main()
