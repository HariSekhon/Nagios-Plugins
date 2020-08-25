#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-08-24 22:33:50 +0100 (Mon, 24 Aug 2020)
#
#  https://github.com/HariSekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/HariSekhon
#

# https://docs.pingdom.com/api/#tag/Checks

"""

Nagios Plugin to check the status, average and max response times of all Pingdom checks via the Pingdom API

Optional thresholds apply to the Pingdom check's max reported response time in ms

Requires $PINGDOM_TOKEN

Generate a token here:

    https://my.pingdom.com/app/api-tokens

Tested on Pingdom.com

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
    from harisekhon.utils import log
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3.0'


class CheckPingdomStatuses(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPingdomStatuses, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Pingdom'
        self.protocol = 'https'
        self.host = 'api.pingdom.com'
        self.port = 443
        self.path = '/api/3.1/checks'
        self.auth = False
        self.json = True
        self.msg = 'Pingdom msg not defined yet'

    def add_options(self):
        self.add_opt('-T', '--token', default=os.getenv('PINGDOM_TOKEN'),
                     help=r'Pingdom authentication token (\$PINGDOM_TOKEN)')
        self.add_thresholds()

    def process_options(self):
        token = self.get_opt('token')
        if not token:
            self.usage('PINGDOM_TOKEN not set, cannot authenticate')
        log.info('setting authorization header')
        self.headers['Authorization'] = 'Bearer {}'.format(token)
        # breaks Pingdom API with 400 Bad Request
        #del self.headers['Content-Type']
        self.validate_thresholds(optional=True)

    def parse_json(self, json_data):
        total = json_data['counts']['total']
        # expand checks for available states:
        # https://docs.pingdom.com/api/#tag/Checks/paths/~1checks/get
        statuses = {
            'up': 0,
            'down': 0,
            'unconfirmed_down': 0,
            'unknown': 0,
            'paused': 0
        }
        max_response_time = 0
        response_times = []
        for check in json_data['checks']:
            statuses[check['status']] += 1
            last_response_time = check['lastresponsetime']
            response_times.append(last_response_time)
            if last_response_time > max_response_time:
                max_response_time = last_response_time
        average_response_time = int(sum(response_times) / len(response_times))
        self.msg = 'Pingdom total checks = {}'.format(total)
        self.msg += ', up = {}'.format(statuses['up'])
        self.msg += ', down = {}'.format(statuses['down'])
        self.msg += ', unconfirmed down = {}'.format(statuses['unconfirmed_down'])
        self.msg += ', unknown = {}'.format(statuses['unknown'])
        self.msg += ', paused = {}'.format(statuses['paused'])
        self.msg += ', average response time = {}ms'.format(average_response_time)
        self.msg += ', max response time = {}ms'.format(max_response_time)
        self.check_thresholds(max_response_time)
        if statuses['down'] + statuses['unconfirmed_down'] > 0:
            self.critical()
        elif statuses['unknown'] + statuses['paused'] > 0:
            self.unknown()
        self.msg += ' | up={}'.format(statuses['up'])
        self.msg += ' down={}'.format(statuses['down'])
        self.msg += ' unconfirmed_down={}'.format(statuses['unconfirmed_down'])
        self.msg += ' unknown={}'.format(statuses['unknown'])
        self.msg += ' paused={}'.format(statuses['paused'])
        self.msg += ' total={}'.format(total)
        self.msg += ' average_response_time={}ms'.format(average_response_time)
        self.msg += ' max_response_time={}ms'.format(max_response_time)
        self.msg += self.get_perf_thresholds()


if __name__ == '__main__':
    CheckPingdomStatuses().main()
