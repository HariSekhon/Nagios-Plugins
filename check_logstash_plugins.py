#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-11-25 23:07:37 +0100 (Sat, 25 Nov 2017)
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

Nagios Plugin to check installed Logstash plugins via the Logstash Rest API

Optionally checks specific plugins are installed and / or number of plugins are within thresholds

API is only available in Logstash 5.x onwards, will get connection refused on older versions

Ensure Logstash options:
  --http.host should be set to 0.0.0.0 if querying remotely
  --http.port should be set to the same port that you are querying via this plugin's --port switch

Tested on Logstash 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1

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
    #from harisekhon.utils import log
    from harisekhon.utils import ERRORS, UnknownError, support_msg_api
    from harisekhon.utils import validate_chars, isList
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckLogstashPlugins(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckLogstashPlugins, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Logstash'
        self.default_port = 9600
        # could add pipeline name to end of this endpoint but error would be less good 404 Not Found
        # Logstash 5.x /_node/pipeline <= use -5 switch for older Logstash
        # Logstash 6.x /_node/pipelines
        self.path = '/_node/plugins'
        self.auth = False
        self.json = True
        self.msg = 'Logstash piplines msg not defined yet'
        self.plugins = None

    def add_options(self):
        super(CheckLogstashPlugins, self).add_options()
        self.add_opt('-u', '--plugins', help='Plugins to check are installed, comma separated (optional)')
        self.add_opt('-l', '--list', action='store_true', help='List plugins and exit')
        self.add_thresholds()

    def process_options(self):
        super(CheckLogstashPlugins, self).process_options()
        plugins = self.get_opt('plugins')
        if plugins:
            self.plugins = [plugin.strip() for plugin in plugins.split(',')]
            for plugin in self.plugins:
                validate_chars(plugin, 'plugin', 'A-Za-z0-9_-')
        self.validate_thresholds(optional=True)

    @staticmethod
    def find_plugin(plugin, plugins):
        for _ in plugins:
            if plugin == _['name']:
                return True
        return False

    def parse_json(self, json_data):
        plugins = json_data['plugins']
        if not isList(plugins):
            raise UnknownError('non-list returned for plugins. {}'.format(support_msg_api()))
        num_plugins = json_data['total']
        if self.get_opt('list'):
            print('Logstash Plugins found = {}:\n'.format(num_plugins))
            for plugin in plugins:
                print('{0}  {1}'.format(plugin['name'], plugin['version']))
            sys.exit(ERRORS['UNKNOWN'])
        self.msg = 'Logstash plugins = {}'.format(num_plugins)
        self.check_thresholds(num_plugins)
        missing_plugins = set()
        if self.plugins:
            for plugin in self.plugins:
                if not self.find_plugin(plugin, plugins):
                    missing_plugins.add(plugin)
        if missing_plugins:
            self.critical()
            self.msg += ', missing plugins: ' + ','.join(sorted(missing_plugins))


if __name__ == '__main__':
    CheckLogstashPlugins().main()
