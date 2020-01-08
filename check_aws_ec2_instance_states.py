#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-01-08 14:55:35 +0000 (Wed, 08 Jan 2020)
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

Nagios Plugin to check AWS EC2 instance states

Gives counts of each state and raises warning for any state other than 'running'

Uses the Boto python library, read here for the list of ways to configure your AWS credentials:

    https://boto3.amazonaws.com/v1/documentation/api/latest/guide/configuration.html

See also DevOps Python Tools and DevOps Bash Tools repos which have more similar AWS tools

- https://github.com/harisekhon/devops-python-tools
- https://github.com/harisekhon/devops-bash-tools

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
import os
import sys
import traceback
from collections import OrderedDict
import boto3
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, jsonpp
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.0'


class CheckAwsEC2InstanceStates(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAwsEC2InstanceStates, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'AWS EC2 states msg not defined'
        self.ok()

    def add_options(self):
        self.add_opt('-p', '--allow-pending', action='store_true', help="Don't raising warning for pending state")
        self.add_opt('-s', '--allow-stopped', action='store_true',
                     help="Don't raising warning for shutting-down / stopping / stopped states")
        self.add_opt('-T', '--allow-terminated', action='store_true', help="Don't raising warning for terminated state")

    def process_args(self):
        self.no_args()

    def run(self):
        log.info('testing AWS API call')
        # there isn't really a .ping() type API endpoint so just connect to IAM and list users
        ec2 = boto3.client('ec2')
        num_instances = 0
        #instances = ec2.describe_instances()
        describe_instances = ec2.get_paginator('describe_instances')
        statuses = OrderedDict(
            [
                ('running', 0),
                ('terminated', 0),
                ('stopped', 0),
                ('stopping', 0),
                ('shutting-down', 0),
            ]
        )
        allow_pending = self.get_opt('allow_pending')
        allow_stopped = self.get_opt('allow_stopped')
        allow_terminated = self.get_opt('allow_terminated')
        flatten = lambda _: [item for sublist in _ for item in sublist]
        # this might time out if there are a lot of EC2 instances
        for instances_response in describe_instances.paginate():
            if log.isEnabledFor(logging.DEBUG):
                log.debug('\n\n%s', jsonpp(instances_response))
            instances = flatten([_['Instances'] for _ in instances_response['Reservations']])
            for instance in instances:
                num_instances += 1
                #if log.isEnabledFor(logging.DEBUG):
                #    log.debug('\n\n%s', instance)
                statuses[instance['State']['Name']] = statuses.get(instance['State']['Name'], 0) + 1
        self.msg = 'AWS EC2 instance total = {}'.format(num_instances)
        for status in statuses:
            self.msg += ', {} = {}'.format(status, statuses[status])
            if status != 'running':
                if (status == 'pending' and allow_pending):
                    pass
                elif status == 'terminated' and allow_terminated:
                    pass
                elif allow_stopped and status in ['shutting-down', 'stopping', 'stopped']:
                    pass
                elif statuses[status] > 0:
                    self.warning()
                    self.msg += ' (!)'
        self.msg += ' | total={}'.format(num_instances)
        for status in statuses:
            self.msg += ' {}={}'.format(status, statuses[status])


if __name__ == '__main__':
    CheckAwsEC2InstanceStates().main()
