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

Queue can also optionally be filtered by those that support a specific browser
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
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


# pylint: disable=too-many-instance-attributes
class CheckSeleniumHubQueue(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckSeleniumHubQueue, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Selenium Hub'
        self.default_port = 4444
        self.path = '/se/grid/newsessionqueuer/queue'
        #self.request_method = 'post'
        #self.path = '/graphql'
        #self.query = '{"query":"{ sessionsInfo { sessionQueueRequests } }"}'
        self.auth = False
        self.json = True
        self.protocol = 'http'
        self.msg = 'Selenium Hub Msg not defined yet'

    def add_options(self):
        super(CheckSeleniumHubQueue, self).add_options()
        self.add_thresholds(default_warning=1, default_critical=1)

    def process_options(self):
        super(CheckSeleniumHubQueue, self).process_options()
        if int(self.port) == 443:
            log_option('ssl inferred by port', True)
            self.protocol = 'https'
        self.validate_thresholds()

    def parse_json(self, json_data):
        items = json_data['value']
        if not isList(items):
            raise UnknownError('non-list returned by API. {}'.format(support_msg_api()))
        queue_size = len(items)
        self.ok()
        self.msg = 'Selenium Hub '
        self.msg += 'queue size = {}'.format(queue_size)
        self.check_thresholds(queue_size)
        self.msg += ' | queue_size={}{}'\
                    .format(queue_size,
                            self.get_perf_thresholds())


if __name__ == '__main__':
    CheckSeleniumHubQueue().main()
