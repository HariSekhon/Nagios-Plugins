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

Nagios Plugin to check AWS CloudTrails have at least 1 event selector enabled and
that for each event selector management events are enabled and ReadWrite type = ALL

Can check one specifically name Cloud Trail or defaults to checking all of them

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
    from harisekhon.utils import CriticalError, ERRORS, log, jsonpp
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1.0'


class CheckAWSCloudTrailEventSelectors(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAWSCloudTrailEventSelectors, self).__init__()
        # Python 3.x
        # super().__init__()
        self.trail_name = None
        self.no_logfile_validation = False
        self.no_multi_region = False
        self.msg = 'CheckAWSCloudTrailEventSelectors msg not defined'
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
            self.msg = 'AWS cloudtrail \'{}\''.format(self.trail_name)
        else:
            self.msg = 'AWS {} cloudtrails'.format(num_trails)
        (num_event_selectors, num_management, num_readwrite_all, trails_without_selectors) \
                = self.process_event_selectors(client, trail_list)
        self.msg += ' event selectors IncludeManagement: {mgt}/{total}, ReadWriteALL: {readwrite}/{total}'\
                    .format(total=num_event_selectors,
                            mgt=num_management,
                            readwrite=num_readwrite_all)
        self.msg += ', trails without event selectors: {}'.format(trails_without_selectors)
        self.msg += ' |'
        self.msg += ' num_trails={}'.format(num_trails)
        self.msg += ' trails_without_event_selectors={}'.format(trails_without_selectors)
        self.msg += ' num_event_selectors={}'.format(num_event_selectors)
        self.msg += ' num_management={}'.format(num_management)
        self.msg += ' num_readwrite_all={}'.format(num_readwrite_all)

    def process_event_selectors(self, client, trail_list):
        total_event_selectors = 0
        num_management = 0
        num_readwrite_all = 0
        trails_without_selectors = 0
        found = False
        for trail in trail_list:
            name = trail['Name']
            if self.trail_name and self.trail_name != name:
                continue
            found = True
            trail_info = client.get_event_selectors(TrailName=name)
            log.debug('%s', jsonpp(trail_info))
            event_selectors = trail_info['EventSelectors']
            num_event_selectors = len(event_selectors)
            total_event_selectors += num_event_selectors
            if num_event_selectors < 1:
                log.warn('cloud trail %s has no event selectors', trail)
                self.warning()
                trails_without_selectors += 1
            for event_selector in event_selectors:
                if event_selector['IncludeManagementEvents']:
                    num_management += 1
                if event_selector['ReadWriteType'].lower() == 'all': # All
                    num_readwrite_all += 1
            if num_management < num_event_selectors or \
               num_readwrite_all < num_event_selectors:
                self.warning()
        if self.trail_name and not found:
            raise CriticalError('cloud trail \'{}\' not found'.format(self.trail_name))
        if total_event_selectors == 0:
            self.warning()
        return (total_event_selectors, num_management, num_readwrite_all, trails_without_selectors)


if __name__ == '__main__':
    CheckAWSCloudTrailEventSelectors().main()
