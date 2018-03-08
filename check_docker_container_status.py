#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-03-07 19:23:22 +0000 (Wed, 07 Mar 2018)
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

Nagios Plugin to check the status of a Docker container via the Docker API

Raises warning if Paused or Restarting

Raises Critical if Exited / Dead / OOMKilled or has a non-zero exit code or Error detected

Outputs start time, plus finished time if exited / dead

Verbose mode outputs the human time since started / finished in brackets

Supports TLS with similar options to official 'docker' command

Tested on Docker 18.02

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

from datetime import datetime
import logging
import os
import sys
import traceback
try:
    import docker
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, jsonpp, CriticalError, sec2human
    from harisekhon.utils import validate_chars
    from harisekhon import DockerNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckDockerContainerStatus(DockerNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckDockerContainerStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'Docker msg not defined'
        self.container = None
        self.expected_id = None

    def add_options(self):
        super(CheckDockerContainerStatus, self).add_options()
        self.add_opt('-C', '--container', help='Docker container name or id')

    def process_options(self):
        super(CheckDockerContainerStatus, self).process_options()
        self.container = self.get_opt('container')
        validate_chars(self.container, 'docker container', r'A-Za-z0-9/:\._-')

    def check(self, client):
        # containers = client.containers.list()
        # print(containers)
        try:
            container = client.containers.get(self.container)
        except docker.errors.APIError as _:
            raise CriticalError(_)
        if log.isEnabledFor(logging.DEBUG):
            log.debug(jsonpp(container.attrs))
        #print(jsonpp(container.stats(stream=False)))
        state = container.attrs['State']
        status = state['Status']
        self.msg = "Docker container '{}' status = '{}'".format(self.container, status)
        if status in ('paused', 'restarting'):
            self.warning()
        elif status != 'running':
            self.critical()
        dead = state['Dead']
        exitcode = state['ExitCode']
        error = state['Error']
        oom = state['OOMKilled']
        restarting = state['Restarting']
        paused = state['Paused']
        started = state['StartedAt']
        finished = state['FinishedAt']
        if paused and status != 'paused':
            self.msg += ", paused = '{}'".format(paused)
            self.warning()
        if restarting and status != 'restarting':
            self.msg += ", restarting = '{}'".format(restarting)
            self.warning()
        if dead:
            self.msg += ", dead = '{}'!".format(dead)
            self.critical()
        if exitcode:
            self.msg += ", exit code = '{}'".format(exitcode)
            self.critical()
        if error:
            self.msg += ", error = '{}'".format(error)
            self.critical()
        if oom:
            self.msg += ", OOMKilled = '{}'".format(oom)
            self.critical()
        self.msg += ", started at '{}'".format(started)
        if self.verbose:
            human_time = self.calculate_human_age(started)
            self.msg += ' ({} ago)'.format(human_time)
        if finished != '0001-01-01T00:00:00Z':
            self.msg += ", finished at '{}'".format(finished)
            if self.verbose:
                human_time = self.calculate_human_age(finished)
                self.msg += ' ({} ago)'.format(human_time)

    @staticmethod
    def calculate_human_age(timestr):
        #started_datetime = time.strptime(started, '%Y-%m-%dT%H:%M:%S.%fZ')
        parsed_datetime = datetime.strptime(timestr.split('.')[0], '%Y-%m-%dT%H:%M:%S')
        time_delta = datetime.now() - parsed_datetime
        secs_ago = time_delta.total_seconds()
        human_time = sec2human(secs_ago)
        return human_time


if __name__ == '__main__':
    CheckDockerContainerStatus().main()
