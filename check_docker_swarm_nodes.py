#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-03-05 19:10:02 +0000 (Mon, 05 Mar 2018)
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

Nagios Plugin to check the number of Docker Swarm worker or manager nodes via the Docker API

Optional thresholds can be applied, defaulting to minimum threshold if not using <min>:<max> range format

Supports TLS with similar options to official 'docker' command

Tested on Docker 18.02

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, jsonpp, CriticalError
    from harisekhon import DockerNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckDockerSwarmNodes(DockerNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckDockerSwarmNodes, self).__init__()
        # Python 3.x
        # super().__init__()
        self.node_type = 'worker'
        self.msg = 'Docker msg not defined yet'

    def add_options(self):
        super(CheckDockerSwarmNodes, self).add_options()
        self.add_opt('-m', '--manager', action='store_true',
                     help='Check number of Swarm Manager nodes rather than workers')
        self.add_thresholds()

    def process_options(self):
        super(CheckDockerSwarmNodes, self).process_options()
        if self.get_opt('manager'):
            self.node_type = 'manager'
        self.validate_thresholds(simple='lower', positive=True, integer=True, optional=True)

    def check(self, client):
        log.info('running Docker info')
        info = client.info()
        if log.isEnabledFor(logging.DEBUG):
            log.debug(jsonpp(info))
        swarm = info['Swarm']
        if 'Cluster' not in swarm:
            raise CriticalError('Docker is not a member of a Swarm')
        if self.node_type == 'manager':
            nodes = swarm['Managers']
        else:
            nodes = swarm['Nodes']
        self.msg = 'Docker Swarm {} nodes = {}'.format(self.node_type, nodes)
        self.check_thresholds(nodes)
        self.msg += ' | docker_swarm_{}_nodes={}{}'.format(self.node_type, nodes, self.get_perf_thresholds('lower'))


if __name__ == '__main__':
    CheckDockerSwarmNodes().main()
