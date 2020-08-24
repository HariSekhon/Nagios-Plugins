#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-08-24 13:37:25 +0100 (Mon, 24 Aug 2020)
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

"""

Nagios Plugin to check Pingdom's remaining available SMS Credits via the Pingdom API

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
    from harisekhon.utils import log, isInt, UnknownError
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1.1'


class CheckPingdomSmsCredits(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPingdomSmsCredits, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Pingdom'
        self.default_host = 'api.pingdom.com'
        self.default_port = 443
        self.path = '/api/3.1/credits'
        self.auth = False
        self.json = True
        self.protocol = 'https'
        self.msg = 'Pingdom msg not defined yet'

    def add_options(self):
        super(CheckPingdomSmsCredits, self).add_options()
        self.add_opt('-T', '--token', default=os.getenv('PINGDOM_TOKEN'),
                     help=r'Pingdom authentication token (\$PINGDOM_TOKEN)')
        self.add_thresholds()

    def process_options(self):
        super(CheckPingdomSmsCredits, self).process_options()
        token = self.get_opt('token')
        if not token:
            self.usage('PINGDOM_TOKEN not set, cannot authenticate')
        log.info('setting authorization header')
        self.headers['Authorization'] = 'Bearer {}'.format(token)
        self.validate_thresholds(simple='lower')
        # breaks Pingdom API with 400 Bad Request
        del self.headers['Content-Type']

    def parse_json(self, json_data):
        sms_credits = json_data['credits']['availablesms']
        if not isInt(sms_credits):
            raise UnknownError('Pingdom API returned non-integer for availablesms field')
        self.msg = 'Pingdom SMS credits available: {}'.format(sms_credits)
        self.check_thresholds(sms_credits)
        self.msg += ' | sms_credits={}'.format(sms_credits)
        self.msg += self.get_perf_thresholds(boundary='lower')


if __name__ == '__main__':
    CheckPingdomSmsCredits().main()
