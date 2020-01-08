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

Nagios Plugin to check the number of running EC2 instances with optional threshold ranges

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
__version__ = '0.1.0'


class CheckAwsEC2InstanceCount(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAwsEC2InstanceCount, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'AWS EC2 instance count msg not defined'
        self.ok()

    def add_options(self):
        self.add_thresholds()

    def process_args(self):
        self.no_args()
        self.validate_thresholds(optional=True)

    def run(self):
        log.info('testing AWS API call')
        # there isn't really a .ping() type API endpoint so just connect to IAM and list users
        ec2 = boto3.client('ec2')
        num_instances = 0
        running_instances = 0
        describe_instances = ec2.get_paginator('describe_instances')
        flatten = lambda _: [item for sublist in _ for item in sublist]
        # this might time out if there are a lot of EC2 instances
        for instances_response in describe_instances.paginate():
            if log.isEnabledFor(logging.DEBUG):
                log.debug('\n\n%s', jsonpp(instances_response))
            instances = flatten([_['Instances'] for _ in instances_response['Reservations']])
            for instance in instances:
                num_instances += 1
                if instance['State']['Name'] == 'running':
                    running_instances += 1
        self.msg = 'AWS EC2 {} running instances'.format(running_instances)
        self.check_thresholds(running_instances)
        self.msg += ' out of {} total instances'.format(num_instances)
        self.msg += ' | total={}'.format(num_instances)
        self.msg += ' running={}{}'.format(running_instances, self.get_perf_thresholds())


if __name__ == '__main__':
    CheckAwsEC2InstanceCount().main()
