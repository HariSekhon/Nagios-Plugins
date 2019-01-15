#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-05-09 18:19:19 +0100 (Wed, 09 May 2018)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback # pylint: disable=line-too-long
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check Apache Drill config settings via its Rest API

Tested on Apache Drill 0.7 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 1.11, 1.12, 1.13, 1.14, 1.15

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import re
import sys
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import RestNagiosPlugin
    from harisekhon.utils import UnknownError, ERRORS, isList, support_msg_api, validate_chars, validate_regex
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckApacheDrillConfig(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckApacheDrillConfig, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Apache Drill'
        self.path = '/options.json'
        self.default_port = 8047
        self.json = True
        self.auth = False
        self.config_key = None
        self.expected_value = None
        self.list_config = False
        self.msg = 'Apache Drill message not defined'

    def add_options(self):
        super(CheckApacheDrillConfig, self).add_options()
        self.add_opt('-k', '--key', help='Config key to check')
        self.add_opt('-e', '--expected', default='.*', help='Expected regex of config value (case insensitive, default: .*)')
        self.add_opt('-l', '--list', action='store_true', help='List settings and exit')

    def process_options(self):
        super(CheckApacheDrillConfig, self).process_options()
        self.config_key = self.get_opt('key')
        self.expected_value = self.get_opt('expected')
        self.list_config = self.get_opt('list')
        if not self.list_config:
            validate_chars(self.config_key, 'config key', r'A-Za-z0-9_\.-')
            validate_regex(self.expected_value, 'expected value regex')

    def parse_json(self, json_data):
        if not isList(json_data):
            raise UnknownError('non-list returned for config settings. {}'.format(support_msg_api()))
        if self.list_config:
            print('Apache Drill config settings:\n')
            for config in json_data:
                print('{} = {}'.format(config['name'], config['value']))
            sys.exit(ERRORS['UNKNOWN'])
        value = None
        for config in json_data:
            name = config['name']
            if name == self.config_key:
                value = config['value']
                break
        if value is None:
            raise UnknownError("config key '{}' not found. See --list for all config keys".format(self.config_key))
        # intentionally using name instead of self.config_key to cause NameError if not set or make error more visible if wrong key match
        self.msg = "Apache Drill config '{}' = '{}'".format(name, value)
        if re.match(str(self.expected_value), str(value), re.I):
            self.ok()
        else:
            self.critical()
            self.msg += " (expected '{}')".format(self.expected_value)


if __name__ == '__main__':
    CheckApacheDrillConfig().main()
