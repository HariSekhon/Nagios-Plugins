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

Nagios Plugin to check Jenkins queued build count via the Rest API

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
    from harisekhon.utils import log, CriticalError, jsonpp
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckJenkinsQueuedBuilds(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsQueuedBuilds, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Jenkins'
        self.default_port = 8080
        self.msg = self.name + ' queued build count = '

    def add_options(self):
        super(CheckJenkinsQueuedBuilds, self).add_options()
        self.add_thresholds(default_warning=10, default_critical=100)

    # can inherently accept AUTH token for password, see:
    # see https://wiki.jenkins-ci.org/display/JENKINS/Authenticating+scripted+clients
    # You can create an API token at:
    # http://jenkins/me/configure
    def process_options(self):
        super(CheckJenkinsQueuedBuilds, self).process_options()
        self.validate_thresholds(optional=True)

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
            log.debug('fetching queued builds')
            queued_builds = server.get_queue_info()
            if log.isEnabledFor(logging.DEBUG):
                log.debug('%s', jsonpp(queued_builds))
            queued_build_count = len(queued_builds)
            log.debug('queued build count: %s', queued_build_count)
            self.msg += '{0}'.format(queued_build_count)
            self.check_thresholds(queued_build_count)
        except jenkins.JenkinsException as _:
            raise CriticalError(_)

        query_time = time.time() - start_time
        self.msg += ' | queued_build_count={0:d}'.format(queued_build_count)
        self.msg += self.get_perf_thresholds()
        self.msg += ' query_time={0:.4f}s'.format(query_time)


if __name__ == '__main__':
    CheckJenkinsQueuedBuilds().main()
