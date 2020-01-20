#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-01-17 16:46:43 +0000 (Fri, 17 Jan 2020)
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

Nagios Plugin to check AWS CloudTrails are enabled / logging,
multi-region and have validation enabled as per best practices

Can check one specifically name Cloud Trail or defaults to checking all of them

Caveats - only checks if it's enabled in the queried region

Uses the Boto python library, read here for the list of ways to configure your AWS credentials:

    https://boto3.amazonaws.com/v1/documentation/api/latest/guide/configuration.html

See also various AWS tools in DevOps Bash Tools and DevOps Python tools repos

- https://github.com/harisekhon/devops-bash-tools
- https://github.com/harisekhon/devops-python-tools

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import sys
import traceback
import boto3
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import ERRORS, CriticalError, log, jsonpp
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1.0'


class CheckAWSCloudTrails(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAWSCloudTrails, self).__init__()
        # Python 3.x
        # super().__init__()
        self.trail_name = None
        self.no_logfile_validation = False
        self.no_multi_region = False
        self.msg = 'CheckAWSCloudTrails msg not defined'
        self.ok()

    def add_options(self):
        self.add_opt('-n', '--name', help='Name of a specific cloud trail to check (defaults to all of them')
        self.add_opt('--no-multi-region', action='store_true',
                     help='Do not require multi-region to be enabled (not recommended)')
        self.add_opt('--no-logfile-validation', action='store_true',
                     help='Do not require logfile validation to be enabled (not recommended)')
        self.add_opt('-l', '--list-trails', action='store_true',
                     help='List trails and exit')

    def process_args(self):
        self.no_args()
        self.trail_name = self.get_opt('name')
        self.no_multi_region = self.get_opt('no_multi_region')
        self.no_logfile_validation = self.get_opt('no_logfile_validation')

    def run(self):
        client = boto3.client('cloudtrail')
        log.info('describing cloud trails')
        _ = client.describe_trails()
        log.debug('%s', jsonpp(_))
        trail_list = _['trailList']
        num_trails = len(trail_list)
        log.info('found %s trails', num_trails)
        if self.get_opt('list_trails'):
            print('Cloud Trails:\n')
            for trail in trail_list:
                print(trail['Name'])
                sys.exit(ERRORS['UNKNOWN'])
        if self.trail_name:
            trail_info = None
            for trail in trail_list:
                name = trail['Name']
                if self.trail_name and self.trail_name != name:
                    continue
                is_multi_region = trail['IsMultiRegionTrail']
                is_logfile_validation = trail['LogFileValidationEnabled']
                trail_info = client.get_trail_status(Name=name)
                log.debug('%s', jsonpp(trail_info))
            if not trail_info:
                raise CriticalError('info for trail \'{}\' not found'.format(self.trail_name))
            is_logging = trail_info['IsLogging']
            if not is_logging:
                self.warning()
            elif not is_multi_region and not self.no_multi_region:
                self.warning()
            elif not is_logfile_validation and not self.no_logfile_validation:
                self.warning()
            self.msg = 'AWS cloudtrail \'{}\' logging: {}, multi-region: {}, logfile-validation-enabled: {}'\
                       .format(self.trail_name, is_logging, is_multi_region, is_logfile_validation)
        else:
            self.check_trails(client, trail_list)

    def check_trails(self, client, trail_list):
        num_trails = len(trail_list)
        num_logging = 0
        num_multi_region = 0
        num_logfile_validation = 0
        for trail in trail_list:
            name = trail['Name']
            if trail['IsMultiRegionTrail']:
                num_multi_region += 1
            if trail['LogFileValidationEnabled']:
                num_logfile_validation += 1
            trail_info = client.get_trail_status(Name=name)
            log.debug('%s', jsonpp(trail_info))
            if trail_info['IsLogging']:
                num_logging += 1
        if num_logging != num_trails:
            self.warning()
        elif num_multi_region != num_trails and not self.no_multi_region:
            self.warning()
        elif num_logfile_validation != num_trails and not self.no_logfile_validation:
            self.warning()
        self.msg = 'AWS cloudtrails logging: {}/{}'.format(num_logging, num_trails)
        self.msg += ', multi-region: {}/{}'.format(num_multi_region, num_trails)
        self.msg += ', validation-enabled: {}/{}'.format(num_logfile_validation, num_trails)
        self.msg += ' | logging={} multi_region={} validation_enabled={}'\
                    .format(num_logging, num_multi_region, num_logfile_validation)


if __name__ == '__main__':
    CheckAWSCloudTrails().main()
