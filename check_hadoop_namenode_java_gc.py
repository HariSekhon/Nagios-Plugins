#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-08-17 18:59:54 +0100 (Fri, 17 Aug 2018)
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

Nagios Plugin to check Hadoop NameNode Java GC last duration via JMX API

Thresholds apply to Java Garbage Collection last duration in seconds

Tested on Apache Hadoop 2.8

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
    from harisekhon.utils import isInt, UnknownError
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckHadoopNameNodeJavaGC(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopNameNodeJavaGC, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Hadoop NameNode', 'Hadoop']
        self.path = '/jmx'
        self.default_port = 50070
        self.json = True
        self.auth = False
        self.msg = 'Hadoop message not defined'

    def add_options(self):
        super(CheckHadoopNameNodeJavaGC, self).add_options()
        self.add_thresholds(default_warning=5, default_critical=10)

    def process_options(self):
        super(CheckHadoopNameNodeJavaGC, self).process_options()
        self.validate_thresholds(integer=False)

    def parse_json(self, json_data):
        gc_times = []
        for bean in json_data['beans']:
            if 'name' in bean and bean['name'][:37] == 'java.lang:type=GarbageCollector,name=':
                last_gc_info = bean['LastGcInfo']
                if last_gc_info and 'duration' in last_gc_info and isInt(last_gc_info['duration']):
                    gc_times.append(int(last_gc_info['duration']))
        if not gc_times:
            raise UnknownError('no Java GC times found')
        gc_millis = max(gc_times)
        gc_millis = int(gc_millis)
        gc_secs = '{:.2f}'.format(gc_millis / 1000)
        self.ok()
        self.msg = '{} Java GC last duration = {} secs'.format(self.name[0], gc_secs)
        self.check_thresholds(gc_secs)
        self.msg += ' | gc_duration={}s{}'.format(gc_secs, self.get_perf_thresholds())


if __name__ == '__main__':
    CheckHadoopNameNodeJavaGC().main()
