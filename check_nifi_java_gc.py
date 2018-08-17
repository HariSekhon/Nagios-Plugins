#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-08-15 23:18:55 +0100 (Wed, 15 Aug 2018)
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

Nagios Plugin to check Nifi Java GC last collection time via its API

Thresholds apply to Java Garbage Collection last collection time in seconds

Tested on Apache Nifi 1.7

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
    from harisekhon.utils import isInt, CriticalError
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckNifiJavaGc(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckNifiJavaGc, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Nifi'
        self.path = '/nifi-api/system-diagnostics'
        self.default_port = 8080
        self.json = True
        self.auth = 'optional'
        self.msg = 'Nifi message not defined'

    def add_options(self):
        super(CheckNifiJavaGc, self).add_options()
        self.add_thresholds(default_warning=3, default_critical=10)

    def process_options(self):
        super(CheckNifiJavaGc, self).process_options()
        self.validate_thresholds(integer=False)

    def parse_json(self, json_data):
        gcs = json_data['systemDiagnostics']['aggregateSnapshot']['garbageCollection']
        gc_millis = max([_['collectionMillis'] for _ in gcs])
        if not isInt(gc_millis):
            raise CriticalError('collectionMillis \'{}\' is not an integer!!'.format(gc_millis))
        gc_millis = int(gc_millis)
        gc_secs = '{:.2f}'.format(gc_millis / 1000)
        self.ok()
        self.msg = 'Nifi Java GC last collection time = {} secs'.format(gc_secs)
        self.check_thresholds(gc_secs)
        self.msg += ' | gc_collection={}s{}'.format(gc_secs, self.get_perf_thresholds())


if __name__ == '__main__':
    CheckNifiJavaGc().main()
