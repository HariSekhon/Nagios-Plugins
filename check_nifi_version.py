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

Nagios Plugin to check the version of a Nifi instance via its API

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
    from harisekhon import RestVersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckNifiVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckNifiVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Nifi'
        self.path = '/nifi-api/system-diagnostics'
        self.default_port = 8080
        self.json = True
        self.auth = 'optional'
        self.msg = 'Nifi message not defined'

    # must be a method for inheritance to work
    def parse_json(self, json_data):  # pylint: disable=no-self-use
        return json_data['systemDiagnostics']['aggregateSnapshot']['versionInfo']['niFiVersion']


if __name__ == '__main__':
    CheckNifiVersion().main()
