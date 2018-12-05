#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-12-05 19:06:22 +0000 (Wed, 05 Dec 2018)
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

Nagios Plugin to check Grafana health via the API

Checks the underlying database status in the API - this checks both Grafana and the underlying db are ok

Authentication is optional, depending on your Grafana installation

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
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckGrafanaHealth(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckGrafanaHealth, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Grafana'
        self.default_port = 3000
        self.path = '/api/health'
        self.auth = 'optional'
        self.json = True
        self.msg = 'Grafana msg not defined yet'

    def add_options(self):
        super(CheckGrafanaHealth, self).add_options()

    def process_options(self):
        super(CheckGrafanaHealth, self).process_options()

    def parse_json(self, json_data):
        database = json_data['database']
        self.msg = 'Grafana and database health = {}'.format(database)
        if database != 'ok':
            self.critical()
            self.msg += " (expected 'ok')"
        version = json_data['version']
        self.msg += ', version = {}'.format(version)


if __name__ == '__main__':
    CheckGrafanaHealth().main()
