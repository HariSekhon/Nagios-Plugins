#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-10-09 16:31:22 +0200 (Mon, 09 Oct 2017)
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

Nagios Plugin to check the Active / Standby state of a Yarn Resource Manager via it's JMX API

Tip: run this against a load balancer in front of your Resource Manager or with
find_active_hadoop_yarn_resource_manager.py to check that you always have an active master available

Tested on Hortonworks HDP 2.6.1 and Apache Hadoop 2.3, 2.4, 2.5, 2.6, 2.7, 2.8

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
    from harisekhon.utils import log_option
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckYarnResourceManagerMasterState(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckYarnResourceManagerMasterState, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Hadoop Yarn Resource Manager'
        self.default_port = 8088
        self.path = '/ws/v1/cluster'
        self.auth = False
        self.json = True
        self.msg = 'Hadoop Yarn Resource Manager HA state = '
        self.expect_active = None
        self.expect_standby = None

    def add_options(self):
        super(CheckYarnResourceManagerMasterState, self).add_options()
        self.add_opt('-a', '--active', action='store_true', help='Expect Active (optional)')
        self.add_opt('-s', '--standby', action='store_true', help='Expect Standby (optional)')

    def process_options(self):
        super(CheckYarnResourceManagerMasterState, self).process_options()
        self.expect_active = self.get_opt('active')
        self.expect_standby = self.get_opt('standby')
        if self.expect_active:
            log_option('expect active', self.expect_active)
        if self.expect_standby:
            log_option('expect standby', self.expect_standby)
        if self.expect_active and self.expect_standby:
            self.usage('cannot specify --expect-active and --expect-standby at the same time' +
                       ', they are mutually exclusive! (omit them if you do not care whether ' +
                       'the master is in active or standby state)')

    def parse_json(self, json_data):
        state = json_data['clusterInfo']['haState']
        self.msg += "'{0}'".format(state)
        if self.expect_active and state != 'ACTIVE':
            self.critical()
            self.msg += ' (expected ACTIVE)'
        if self.expect_standby and state != 'STANDBY':
            self.critical()
            self.msg += ' (expected STANDBY)'


if __name__ == '__main__':
    CheckYarnResourceManagerMasterState().main()
