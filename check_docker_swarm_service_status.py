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

Nagios Plugin to check the status of a Docker Swarm service via the Docker API

Raises CRITICAL if the service does not exist or if the node is not a Swarm Manager

Optional --warning / --critical thresholds apply to minimum number of running tasks for the service
(can also use min:max threshold range format)

Outputs service creation time time and last updated time

Verbose mode outputs the human time since started / finished in brackets

Optional --warn-if-last-updated-within threshold raises warning if the service was updated
less than the given number of seconds ago

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
    from harisekhon.utils import log, jsonpp, CriticalError, UnknownError, sec2human, support_msg_api
    from harisekhon.utils import validate_chars, validate_int
    from harisekhon import DockerNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.5'


class CheckDockerSwarmServiceStatus(DockerNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckDockerSwarmServiceStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'Docker msg not defined'
        self.service = None
        self.updated = None
        self.expected_id = None

    def add_options(self):
        super(CheckDockerSwarmServiceStatus, self).add_options()
        self.add_opt('-S', '--service', help='Docker Swarm service name or id')
        self.add_opt('-U', '--warn-if-last-updated-within',
                     help='Raise warning if service was updated within this may secs ago')
        self.add_thresholds()

    def process_options(self):
        super(CheckDockerSwarmServiceStatus, self).process_options()
        self.service = self.get_opt('service')
        self.updated = self.get_opt('warn_if_last_updated_within')
        validate_chars(self.service, 'docker service', r'A-Za-z0-9/:\._-')
        if self.updated is not None:
            validate_int(self.updated, 'last updated threshold')
            self.updated = int(self.updated)
        self.validate_thresholds(simple='lower', positive=True, optional=True)

    def check(self, client):
        # services = client.services.list()
        # print(services)
        try:
            service = client.services.get(self.service)
        except docker.errors.APIError as _:
            raise CriticalError(_)
        if log.isEnabledFor(logging.DEBUG):
            log.debug(jsonpp(service.attrs))
        (mode, replicas, running_tasks, created, updated) = self.parse_service(service)
        self.msg = "Docker Swarm service '{}' replicas = {}".format(self.service, running_tasks)
        if mode == 'replicated':
            self.msg += "/{}".format(replicas)
        self.check_thresholds(running_tasks)
        if not running_tasks:
            self.critical()
        if mode != 'replicated':
            self.msg += ", mode = '{}'".format(mode)
            for _ in ('critical', 'warning'):
                thresholds = self.get_threshold(_, optional=True).thresholds
                if thresholds['upper'] or thresholds['lower']:
                    self.critical()
                    self.msg += ' (but --{} replica threshold expects replicated mode!)'.format(_)
                    break
        self.check_created(created)
        self.check_updated(updated)
        self.msg += ' | running_replicas={}{}'.format(running_tasks, self.get_perf_thresholds('lower'))

    @staticmethod
    def parse_service(service):
        _ = service.attrs
        _mode = _['Spec']['Mode']
        if 'Global' in _mode:
            mode = 'global'
            replicas = None
        elif 'Replicated' in _mode:
            mode = 'replicated'
            replicas = _mode['Replicated']['Replicas']
        else:
            raise UnknownError('failed to parse service mode. {}'.format(support_msg_api()))
        tasks = service.tasks()
        if log.isEnabledFor(logging.DEBUG):
            log.debug(jsonpp(tasks))
        running_tasks = 0
        for task in tasks:
            if task['Status']['State'] == 'running':
                running_tasks += 1
        created = _['CreatedAt']
        updated = _['UpdatedAt']
        return (mode, replicas, running_tasks, created, updated)

    def check_created(self, created):
        self.msg += ", created at '{}'".format(created)
        if self.verbose:
            (human_time, _) = self.calculate_human_age(created)
            self.msg += ' ({} ago)'.format(human_time)

    def check_updated(self, updated):
        self.msg += ", updated at '{}'".format(updated)
        (human_time, secs_ago) = self.calculate_human_age(updated)
        if self.verbose:
            self.msg += ' ({} ago)'.format(human_time)
        if self.updated and secs_ago < self.updated:
            self.warning()
            self.msg += ' (< {} secs ago)'.format(self.updated)

    @staticmethod
    def calculate_human_age(timestr):
        #started_datetime = time.strptime(started, '%Y-%m-%dT%H:%M:%S.%fZ')
        parsed_datetime = datetime.strptime(timestr.split('.')[0], '%Y-%m-%dT%H:%M:%S')
        time_delta = datetime.now() - parsed_datetime
        secs_ago = time_delta.total_seconds()
        human_time = sec2human(secs_ago)
        return (human_time, secs_ago)


if __name__ == '__main__':
    CheckDockerSwarmServiceStatus().main()
