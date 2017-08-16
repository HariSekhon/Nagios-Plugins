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

Nagios Plugin to check if installed Jenkins plugins have updates available via the Rest API

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
    from harisekhon.utils import log, CriticalError, jsonpp, plural
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.2'


class CheckJenkinsPluginUpdates(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsPluginUpdates, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Jenkins'
        self.default_port = 8080
        self.msg = self.name

    #def add_options(self):
    #    super(CheckJenkinsPluginUpdates, self).add_options()

    # can inherently accept AUTH token for password, see:
    # see https://wiki.jenkins-ci.org/display/JENKINS/Authenticating+scripted+clients
    # You can create an API token at:
    # http://jenkins/me/configure
#    def process_options(self):
#        super(CheckJenkinsPluginUpdates, self).process_options()

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
        plugin_count = len(plugins)
        update_count = 0
        for plugin in plugins:
            if plugin['hasUpdate']:
                update_count += 1
        self.msg += " {0} plugin update{1} available out of {2} installed plugin{3}".format(update_count,
                                                                                            plural(update_count),
                                                                                            plugin_count,
                                                                                            plural(plugin_count))
        if update_count:
            self.warning()
        self.msg += ' | updates_available={0};1 plugins_installed={1} query_time={2:.4f}s'.format(update_count,
                                                                                                  plugin_count,
                                                                                                  query_time)


if __name__ == '__main__':
    CheckJenkinsPluginUpdates().main()
