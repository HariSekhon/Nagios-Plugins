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

# https://docs.pingdom.com/api/#tag/Checks/paths/~1checks~1{checkid}/get

"""

Nagios Plugin to check the status and response time of a Pingdom check via the Pingdom API

Optional thresholds apply to the Pingdom check's reported response time in ms

Requires $PINGDOM_TOKEN

Generate a token here:

    https://my.pingdom.com/app/api-tokens

Tested on Pingdom.com

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import json
import logging
import os
import sys
import time
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, isInt, ERRORS, jsonpp
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3.0'


class CheckPingdomStatus(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPingdomStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Pingdom'
        self.protocol = 'https'
        self.host = 'api.pingdom.com'
        self.port = 443
        self.path = '/api/3.1/checks/'
        self.auth = False
        self.json = True
        self.max_check_age = None
        self.msg = 'Pingdom msg not defined yet'

    def add_options(self):
        self.add_opt('-i', '--check-id', help='ID of the Pingdom check (required, find this from --list)')
        self.add_opt('-m', '--max-check-age', type=int, default=300,
                     help='Max age of the pingdom check in seconds (default: 300)')
        self.add_opt('-T', '--token', default=os.getenv('PINGDOM_TOKEN'),
                     help=r'Pingdom authentication token (\$PINGDOM_TOKEN)')
        self.add_opt('-l', '--list', action='store_true', help='List Pingdom checks and exit')
        self.add_thresholds()

    def process_options(self):
        _id = self.get_opt('check_id')
        if not isInt(_id):
            self.usage('non-integer given as check id')
        self.path += _id
        token = self.get_opt('token')
        if not token:
            self.usage('PINGDOM_TOKEN not set, cannot authenticate')
        log.info('setting authorization header')
        self.headers['Authorization'] = 'Bearer {}'.format(token)
        # breaks Pingdom API with 400 Bad Request
        #del self.headers['Content-Type']
        if self.get_opt('list'):
            self.list_checks()
        self.validate_thresholds(optional=True)
        self.max_check_age = self.get_opt('max_check_age')

    def list_checks(self):
        self.path = '/api/3.1/checks'
        req = self.query()
        json_data = json.loads(req.content)
        if log.isEnabledFor(logging.DEBUG):
            log.debug('JSON prettified:\n\n%s\n%s', jsonpp(json_data), '='*80)
        print('Pingdom checks:\n')
        for check in json_data['checks']:
            print('{id}\t{name}\t{type}\t{hostname}\t{status}'.format(
                id=check['id'],
                name=check['name'],
                type=check['type'],
                hostname=check['hostname'],
                status=check['status']
            ))
        sys.exit(ERRORS['UNKNOWN'])

    def parse_json(self, json_data):
        check = json_data['check']
        status = check['status']
        last_response_time = check['lastresponsetime']
        hostname = check['hostname']
        last_test_time = check['lasttesttime']
        last_tested_secs = int(time.time() - last_test_time)
        _id = check['id']
        try:
            proto = 'http'
            if check['type']['http']['encryption']:
                proto = 'https'
            url = '{proto}://{host}:{port}{url}'.format(
                proto=proto,
                host=hostname,
                port=check['type']['http']['port'],
                url=check['type']['http']['url'])
            self.msg = 'Pingdom check id {id} status = {status}, url = {url}'.format(
                id=_id,
                status=status,
                url=url)
        except KeyError:
            self.msg = 'Pingdom check id {} status = {}, hostname = {}'.format(_id, status, hostname)
        status_code = 1  # ok
        # expand checks for available states:
        # https://docs.pingdom.com/api/#tag/Checks/paths/~1checks/get
        if status in ("unknown", "paused"):
            self.unknown()
            status_code = 0
        if status != 'up':
            status_code = 0
            self.critical()
        self.msg += ', last response time = {}ms'.format(last_response_time)
        self.check_thresholds(last_response_time)
        self.msg += ', last tested {} secs ago'.format(last_tested_secs)
        if last_tested_secs > self.max_check_age:
            self.warning()
            self.msg += ' (> 300)'
        self.msg += ' | status={}'.format(status_code)
        self.msg += ' last_response_time={}ms'.format(last_response_time)
        self.msg += self.get_perf_thresholds()


if __name__ == '__main__':
    CheckPingdomStatus().main()
