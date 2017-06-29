#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-06-22 22:29:37 +0200 (Thu, 22 Jun 2017)
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

Nagios Plugin to check a Jenkins plugin is enabled and active via the Rest API

Lists if an update is available for the plugin and if --check-update is specified then raises a warning

The --password switch accepts either a password or an API token

Tested on Jenkins 2.60.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
import os
import sys
import time
import traceback
try:
    import jenkins
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, log_option, CriticalError, ERRORS, jsonpp, validate_chars
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckJenkinsPlugin(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsPlugin, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Jenkins'
        self.default_port = 8080
        self.msg = self.name
        self.plugin = None
        self.list_plugins = False
        self.check_update = False

    def add_options(self):
        super(CheckJenkinsPlugin, self).add_options()
        self.add_opt('-n', '--plugin', metavar='name',
                     help='Plugin long name eg. \'Jenkins Git plugin\' (case insensitive)')
        self.add_opt('-l', '--list', action='store_true', help='List plugins and exit')
        self.add_opt('-U', '--check-update', action='store_true', help='Warn if an update is available')

    # can inherently accept AUTH token for password, see:
    # see https://wiki.jenkins-ci.org/display/JENKINS/Authenticating+scripted+clients
    # You can create an API token at:
    # http://jenkins/me/configure
    def process_options(self):
        super(CheckJenkinsPlugin, self).process_options()
        self.plugin = self.get_opt('plugin')
        self.list_plugins = self.get_opt('list')
        if not self.list_plugins:
            validate_chars(self.plugin, 'plugin', r'A-Za-z0-9\s\.,_-')
        self.check_update = self.get_opt('check_update')
        log_option('check for updates', self.check_update)

    def run(self):
        server_url = '{proto}://{host}:{port}'.format(proto=self.protocol, host=self.host, port=self.port)
        try:
            log.debug('setting up Jenkins connection to %s', server_url)
            start_time = time.time()
            server = jenkins.Jenkins(server_url, username=self.user, password=self.password, timeout=self.timeout / 3)
            if log.isEnabledFor(logging.DEBUG):
                log.debug('getting user')
                user = server.get_whoami()
                log.debug('connected as user %s', jsonpp(user))
            log.debug('getting plugin info')
            #plugins = server.get_plugins()
            # deprecated but .get_plugins() output is not JSON serializable
            # so must use old deprecated method get_plugins_info() :-/
            plugins = server.get_plugins_info()
            query_time = time.time() - start_time
        except jenkins.JenkinsException as _:
            raise CriticalError(_)

        if log.isEnabledFor(logging.DEBUG):
            log.debug('%s', jsonpp(plugins))
        if self.list_plugins:
            plugin_list = []
            print('Jenkins plugins:\n')
            for _ in plugins:
                plugin_list.append(_['longName'])
            for _ in sorted(plugin_list, key=lambda s: s.lower()):
                print(_)
            sys.exit(ERRORS['UNKNOWN'])
        plugin = None
        for _ in plugins:
            if _['longName'].lower() == self.plugin.lower():
                plugin = _
                break
        if not plugin:
            raise CriticalError("plugin '{0}' not found. Try --list to see installed plugins".format(self.plugin))
        longname = plugin['longName']
        enabled = plugin['enabled']
        active = plugin['active']
        has_update = plugin['hasUpdate']
        self.msg += " plugin '{0}' enabled: {1}, active: {2}".format(longname, enabled, active)
        if not enabled or not active:
            self.critical()
        self.msg += ', update available: {0}'.format(has_update)
        if self.check_update and has_update:
            self.warning()
        self.msg += ' | query_time={0:.4f}s'.format(query_time)


if __name__ == '__main__':
    CheckJenkinsPlugin().main()
