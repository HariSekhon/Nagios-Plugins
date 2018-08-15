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

Nagios Plugin to check Nifi is online via its API

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
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckNifiStatus(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckNifiStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Nifi'
        self.path = '/nifi-api/system-diagnostics'
        self.default_port = 8080
        self.json = True
        self.auth = 'optional'
        self.msg = 'Nifi message not defined'

    def parse_json(self, json_data):
        processors = json_data['systemDiagnostics']['aggregateSnapshot']['availableProcessors']
        if not isInt(processors):
            raise CriticalError('availableProcessors \'{}\' is not an integer!!'.format(processors))
        processors = int(processors)
        if processors > 0:
            self.ok()
            self.msg = 'Nifi status = OK, processors available'
        else:
            self.critical()
            self.msg = 'Nifi status = CRITICAL, no processors available'


if __name__ == '__main__':
    CheckNifiStatus().main()
