#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2021-05-16 09:59:33 +0100 (Sun, 16 May 2021)
#
#  https://github.com/HariSekhon/Nagios-Plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/HariSekhon
#

"""

Nagios Plugin to check the number of nodes available on a Selenium Hub via its Rest API

Optional warning / critical thresholds apply to the lower bound number of nodes

Nodes can also optionally be filtered by those that support a specific browser
(eg. 'firefox' or 'chrome') to check on each pool's availability

Tested on Selenium Grid Hub 4.0.0 (API node info not available in 3.x or Selenoid 1.10)

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
    from harisekhon.utils import log_option, isList, UnknownError, support_msg_api
    from harisekhon import RestNagiosPlugin
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


# pylint: disable=too-many-instance-attributes
class CheckSeleniumHubNodes(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckSeleniumHubNodes, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Selenium Hub'
        self.default_port = 4444
        self.path = '/wd/hub/status'
        # or just
        #self.path = '/status'
        self.auth = False
        self.json = True
        self.protocol = 'http'
        self.browser = None
        self.msg = 'Selenium Hub Msg not defined yet'

    def add_options(self):
        super(CheckSeleniumHubNodes, self).add_options()
        self.add_opt('-b', '--browser', help='Browser filter (eg. chrome, firefox)')
        self.add_thresholds(default_warning=1, default_critical=1)

    def process_options(self):
        super(CheckSeleniumHubNodes, self).process_options()
        if int(self.port) == 443:
            log_option('ssl inferred by port', True)
            self.protocol = 'https'
        self.browser = self.get_opt('browser')
        log_option('browser filter', self.browser)
        self.validate_thresholds(simple='lower')

    def parse_json(self, json_data):
        data = json_data['value']
        try:
            nodes = data['nodes']
        except KeyError:
            raise UnknownError('nodes field not found, are you trying to run this on an old ' +
                               'Selenium Hub <= 3.x or Selenoid? That information is not available in those APIs')
        if not isList(nodes):
            raise UnknownError('nodes field is not a list as expected. {}'.format(support_msg_api()))
        total_nodes = 0
        available_nodes = 0
        for node in nodes:
            if self.browser:
                supports_browser = False
                for slot in node['slots']:
                    if slot['stereotype']['browserName'].lower() == self.browser.lower():
                        supports_browser = True
                        break
                if not supports_browser:
                    continue
            total_nodes += 1
            if node['availability'] == 'UP':
                available_nodes += 1
        self.ok()
        self.msg = 'Selenium Hub '
        if self.browser:
            self.msg += "'{}' ".format(self.browser)
        self.msg += 'nodes available = {}/{}'.format(available_nodes, total_nodes)
        self.check_thresholds(available_nodes)
        self.msg += ' | nodes_available={}{} nodes_total={}'\
                    .format(available_nodes,
                            self.get_perf_thresholds(boundary='lower'),
                            total_nodes)


if __name__ == '__main__':
    CheckSeleniumHubNodes().main()
