#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-05-04 18:35:36 +0100 (Fri, 04 May 2018)
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

Nagios Plugin to check an Apache Drill storage plugin is enabled via the Drillbit's Rest API

Tested on Apache Drill 0,7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 1.11, 1.12, 1.13, 1.14, 1.15

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import RestNagiosPlugin
    from harisekhon.utils import UnknownError, CriticalError, ERRORS, isList, support_msg_api
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckApacheDrillStoragePlugin(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckApacheDrillStoragePlugin, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Apache Drill'
        self.path = '/storage.json'
        self.default_port = 8047
        self.json = True
        self.auth = False
        self.storage_plugin = None
        self.msg = 'Apache Drill message not defined'

    def add_options(self):
        super(CheckApacheDrillStoragePlugin, self).add_options()
        self.add_opt('-n', '--name', default='dfs', help='Name of the storage plugin to check (default: dfs)')
        self.add_opt('-T', '--type', help='Type of the storage plugin to expect (optional)')
        self.add_opt('-l', '--list', action='store_true', help='List storage plugins and exit')

    def process_options(self):
        super(CheckApacheDrillStoragePlugin, self).process_options()
        self.storage_plugin = self.get_opt('name')

    def parse_json(self, json_data):
        if not isList(json_data):
            raise UnknownError('non-list returned for storage plugins. {}'.format(support_msg_api()))
        if self.get_opt('list'):
            print('Apache Drill storage plugins:\n')
            print('=' * 50)
            print('%-10s\t%-10s\t%s' % ('Name', 'Type', 'Enabled'))
            print('=' * 50 + '\n')
            for storage_plugin in json_data:
                name = storage_plugin['name']
                config = storage_plugin['config']
                plugin_type = config['type']
                enabled = config['enabled']
                print('%-10s\t%-10s\t%s' % (name, plugin_type, enabled))
            sys.exit(ERRORS['UNKNOWN'])

        config = None
        for storage_plugin in json_data:
            name = storage_plugin['name']
            if name == self.storage_plugin:
                config = storage_plugin['config']
                plugin_type = config['type']
                enabled = config['enabled']
                break
        if not config:
            raise CriticalError("Apache Drill storage plugin '{}' not found! See --list for available plugins!"\
                                .format(self.storage_plugin))
        self.msg = "Apache Drill storage plugin '{}' enabled = {}, plugin type = '{}'"\
                   .format(self.storage_plugin, enabled, plugin_type)
        if not enabled:
            self.critical()
        _type = self.get_opt('type')
        if _type and _type != plugin_type:
            self.critical()
            self.msg += " (expected '{}')".format(_type)


if __name__ == '__main__':
    CheckApacheDrillStoragePlugin().main()
