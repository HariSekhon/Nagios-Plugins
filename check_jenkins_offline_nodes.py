#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-06-28 23:12:52 +0200 (Wed, 28 Jun 2017)
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

Nagios Plugin to check for offline Jenkins nodes via the Rest API

Thresholds apply to the max number of offline nodes

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
__version__ = '0.1'


class CheckJenkinsOfflineNodes(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsOfflineNodes, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Jenkins'
        self.default_port = 8080
        self.msg = self.name + ': '

    def add_options(self):
        super(CheckJenkinsOfflineNodes, self).add_options()
        self.add_thresholds(default_warning=0, default_critical=1)

    # can inherently accept AUTH token for password, see:
    # see https://wiki.jenkins-ci.org/display/JENKINS/Authenticating+scripted+clients
    # You can create an API token at:
    # http://jenkins/me/configure
    def process_options(self):
        super(CheckJenkinsOfflineNodes, self).process_options()
        self.validate_thresholds()

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
            log.debug('getting Jenkins nodes')
            nodes = server.get_nodes()
            log.debug('nodes: %s', nodes)
            node_count = len(nodes)
            log.debug('node count: %s', node_count)
            offline_nodes = 0
            for node in nodes:
                if node['offline']:
                    offline_nodes += 1
            self.msg += '{0} offline node{1}'.format(offline_nodes, plural(offline_nodes))
            self.check_thresholds(offline_nodes)
            self.msg += ' out of {0} node{1}'.format(node_count, plural(node_count))
        except jenkins.JenkinsException as _:
            raise CriticalError(_)

        query_time = time.time() - start_time
        self.msg += ' | offline_nodes={0:d}'.format(offline_nodes)
        self.msg += self.get_perf_thresholds()
        self.msg += ' node_count={0:d}'.format(node_count)
        self.msg += ' query_time={0:.4f}s'.format(query_time)


if __name__ == '__main__':
    CheckJenkinsOfflineNodes().main()
