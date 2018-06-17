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

Nagios Plugin to check the number of Docker containers via the Docker API

Optional thresholds can be applied if specifying a single container option

Perfdata is output for graphing the number of containers over time

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
    from harisekhon.utils import log, jsonpp
    from harisekhon import DockerNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckDockerContainers(DockerNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckDockerContainers, self).__init__()
        # Python 3.x
        # super().__init__()
        self.running = False
        self.paused = False
        self.stopped = False
        self.total = False
        self.msg = 'Docker msg not defined yet'

    def add_options(self):
        super(CheckDockerContainers, self).add_options()
        self.add_opt('-r', '--running', action='store_true', help='Check running containers')
        self.add_opt('-p', '--paused', action='store_true', help='Check paused containers')
        self.add_opt('-s', '--stopped', action='store_true', help='Check stopped containers')
        self.add_opt('-a', '--total', action='store_true', help='Check total containers')
        self.add_thresholds()

    def process_options(self):
        super(CheckDockerContainers, self).process_options()
        self.running = self.get_opt('running')
        self.paused = self.get_opt('paused')
        self.stopped = self.get_opt('stopped')
        self.total = self.get_opt('total')
        _ = bool(self.running) + bool(self.paused) + bool(self.stopped) + bool(self.total)
        if _ == 1:
            self.validate_thresholds(positive=True, integer=True, optional=True)
        if _ > 1:
            self.usage('--running / --paused / --stopped / --total are mutually exclusive threshold checks')

    def check(self, client):
        log.info('running Docker info')
        info = client.info()
        if log.isEnabledFor(logging.DEBUG):
            log.debug(jsonpp(info))
        containers = info['Containers']
        running_containers = info['ContainersRunning']
        paused_containers = info['ContainersPaused']
        stopped_containers = info['ContainersStopped']
        self.msg = 'Docker '
        if self.running:
            self.msg += 'running containers = {}'.format(running_containers)
            self.check_thresholds(running_containers)
            self.msg += ' | running_containers={}{}'.format(running_containers, self.get_perf_thresholds())
        elif self.paused:
            self.msg += 'paused containers = {}'.format(paused_containers)
            self.check_thresholds(paused_containers)
            self.msg += ' | paused_containers={}{}'.format(paused_containers, self.get_perf_thresholds())
        elif self.stopped:
            self.msg += 'stopped containers = {}'.format(stopped_containers)
            self.check_thresholds(stopped_containers)
            self.msg += ' | stopped_containers={}{}'.format(stopped_containers, self.get_perf_thresholds())
        elif self.total:
            self.msg += 'total containers = {}'.format(containers)
            self.check_thresholds(containers)
            self.msg += ' | total_containers={}{}'.format(containers, self.get_perf_thresholds())
        else:
            self.msg += 'containers = {}, running containers = {}, paused containers = {}, stopped containers = {}'\
                       .format(containers, running_containers, paused_containers, stopped_containers)
            self.msg += ' | containers={} running_containers={} paused_containers={} stopped_containers={}'\
                        .format(containers, running_containers, paused_containers, stopped_containers)


if __name__ == '__main__':
    CheckDockerContainers().main()
