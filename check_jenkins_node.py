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

Nagios Plugin to check a given Jenkins node is online and the number of executors is has via the Rest API

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
    from harisekhon.utils import log, ERRORS, CriticalError, UnknownError, \
                                 jsonpp, validate_chars, isInt, support_msg_api
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckJenkinsNode(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsNode, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Jenkins'
        self.default_port = 8080
        self.msg = self.name + ' node '
        self.node = None
        self.list_nodes = False

    def add_options(self):
        super(CheckJenkinsNode, self).add_options()
        self.add_opt('-n', '--node', help='Node to check')
        self.add_opt('-l', '--list', action='store_true', help='List nodes and exit')
        self.add_thresholds(default_warning=2, default_critical=1)

    # can inherently accept AUTH token for password, see:
    # see https://wiki.jenkins-ci.org/display/JENKINS/Authenticating+scripted+clients
    # You can create an API token at:
    # http://jenkins/me/configure
    def process_options(self):
        super(CheckJenkinsNode, self).process_options()
        self.node = self.get_opt('node')
        self.list_nodes = self.get_opt('list')
        if not self.list_nodes:
            validate_chars(self.node, 'node', r'A-Za-z0-9\._-')
            self.msg += '{0} is '.format(self.node)
        self.validate_thresholds(simple='lower')

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
            if self.list_nodes:
                log.debug('getting Jenkins nodes')
                nodes = server.get_nodes()
                log.debug('nodes: %s', nodes)
                print('Jenkins nodes:\n')
                for _ in nodes:
                    print(_['name'])
                sys.exit(ERRORS['UNKNOWN'])
            # doesn't find 'master' node despite showing it in the list of nodes, jenkins puts brackets around master
            if self.node == 'master':
                self.node = '(master)'
            node = server.get_node_info(self.node)
        except jenkins.NotFoundException:
            raise CriticalError("node '{0}' not found, did you specify the correct name? See --list to see nodes"\
                                .format(self.node))
        except jenkins.JenkinsException as _:
            raise CriticalError(_)

        query_time = time.time() - start_time
        if log.isEnabledFor(logging.DEBUG):
            log.debug('%s', jsonpp(node))
        offline = node['offline']
        offline_reason = node['offlineCauseReason']
        num_executors = node['numExecutors']
        num_executors = int(num_executors)
        if not isInt(num_executors):
            raise UnknownError('numExecutors returned non-integer! {0}'.format(support_msg_api()))
        if offline:
            self.critical()
            self.msg += 'offline: {0}'.format(offline_reason)
        else:
            self.msg += 'online'
        self.msg += ', num executors = {0}'.format(num_executors)
        self.check_thresholds(num_executors)
        self.msg += ' | num_executors={0:d}'.format(num_executors)
        self.msg += self.get_perf_thresholds(boundary='lower')
        self.msg += ' query_time={0:.4f}s'.format(query_time)


if __name__ == '__main__':
    CheckJenkinsNode().main()
