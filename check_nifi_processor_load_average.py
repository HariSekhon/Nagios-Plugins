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

Nagios Plugin to check Nifi processor load average via its API

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
    from harisekhon.utils import isFloat, CriticalError
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckNifiProcessorLoadAverage(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckNifiProcessorLoadAverage, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Nifi'
        self.path = '/nifi-api/system-diagnostics'
        self.default_port = 8080
        self.json = True
        self.auth = 'optional'
        self.msg = 'Nifi message not defined'

    def add_options(self):
        super(CheckNifiProcessorLoadAverage, self).add_options()
        self.add_thresholds(default_warning=0.7, default_critical=0.9)

    def process_options(self):
        super(CheckNifiProcessorLoadAverage, self).process_options()
        self.validate_thresholds(integer=False, min=0, max=1)

    def parse_json(self, json_data):
        load_average = json_data['systemDiagnostics']['aggregateSnapshot']['processorLoadAverage']
        if not isFloat(load_average):
            raise CriticalError('processorLoadAverage \'{}\' is not a float!!'.format(load_average))
        load_average = float(load_average)
        self.ok()
        self.msg = 'Nifi processor load average = {}'.format(load_average)
        self.check_thresholds(load_average)
        self.msg += ' | processor_load_average={}{}'.format(load_average, self.get_perf_thresholds())


if __name__ == '__main__':
    CheckNifiProcessorLoadAverage().main()
