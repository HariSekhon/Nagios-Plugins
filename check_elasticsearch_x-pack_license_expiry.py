#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-03-05 19:09:03 +0000 (Mon, 05 Mar 2018)
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

Nagios Plugin to check Elasticsearch X-Pack license expiry in days via the X-Pack API

Tested on Elasticsearch with X-Pack 6.0, 6.1, 6.2, 7.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import time
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
__version__ = '0.2'


class CheckElasticsearchXPackLicenseExpiry(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckElasticsearchXPackLicenseExpiry, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Elasticsearch'
        self.default_port = 9200
        # /_xpack contains info on enabled features but less expiry info (no expiry date or start_date_in_millis)
        self.path = '/_xpack/license?human=true'
        self.auth = 'optional'
        self.json = True
        self.msg = 'Elasticsearch msg not defined yet'

    def add_options(self):
        super(CheckElasticsearchXPackLicenseExpiry, self).add_options()
        self.add_opt('-B', '--basic', action='store_true', help='Do not raise WARNING for basic license')
        self.add_opt('-T', '--trial', action='store_true', help='Do not raise WARNING for trial license')
        self.add_thresholds(default_warning=30, default_critical=7)

    def process_options(self):
        super(CheckElasticsearchXPackLicenseExpiry, self).process_options()
        self.validate_thresholds(simple='lower', positive=True, integer=False)

    def parse_json(self, json_data):
        license_data = json_data['license']
        status = license_data['status']
        license_type = license_data['type']
        start_millis = license_data['start_date_in_millis']
        self.msg = "Elasticsearch X-Pack license '{}'".format(status)
        if status != 'active':
            self.critical()
            self.msg += '(!)'
        self.msg += ", type: '{}'".format(license_type)
        if license_type == 'trial':
            if not self.get_opt('trial'):
                self.warning()
                self.msg += '(!)'
        elif license_type == 'basic':
            if not self.get_opt('basic'):
                self.warning()
                self.msg += '(!)'
            return
        expiry_millis = license_data['expiry_date_in_millis']
        # start_date is only available with ?human=true which is not enabled by default
        expiry_date = license_data['expiry_date']
        days_left = int((expiry_millis - time.time() * 1000) / 1000 / 86400)
        if days_left < 0:
            self.critical()
            self.msg += ' LICENSE EXPIRED {} days ago'.format(days_left)
        else:
            self.msg += ', expires in {} days'.format(days_left)
            self.check_thresholds(days_left)
        self.msg += " on '{}'".format(expiry_date)
        if start_millis > (time.time() * 1000):
            # start_date string field available with ?human=true, don't have to calculate
            #start_date = time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(start_millis / 1000))
            start_date = license_data['start_date']
            self.msg += ", but start date '{}' is in the future!!!".format(start_date)
            self.warning()


if __name__ == '__main__':
    CheckElasticsearchXPackLicenseExpiry().main()
