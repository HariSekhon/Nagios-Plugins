#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-01-21 17:35:28 +0000 (Tue, 21 Jan 2020)
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

Nagios Plugin to check AWS Config is enabled and recording

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


class CheckAWSConfig(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAWSConfig, self).__init__()
        # Python 3.x
        # super().__init__()
        self.recorder_name = None
        self.msg = 'CheckAWSConfig msg not defined'
        self.ok()

    def add_options(self):
        self.add_opt('-n', '--name', help='Name of a specific config record to check (defaults to all of them')
        self.add_opt('-l', '--list-recorders', action='store_true',
                     help='List trails and exit')

    def process_args(self):
        self.no_args()
        self.recorder_name = self.get_opt('name')

    def run(self):
        client = boto3.client('config')
        log.info('describing config recorders')
        _ = client.describe_configuration_recorder_status()
        log.debug('%s', jsonpp(_))
        recorders = _['ConfigurationRecordersStatus']
        num_recorders = len(recorders)
        log.info('found %s recorders', num_recorders)
        if self.get_opt('list_recorders'):
            print('Config Recorders:\n')
            for recorder in recorders:
                print(recorder['name'])
                sys.exit(ERRORS['UNKNOWN'])
        if self.recorder_name:
            recorder_info = None
            for recorder in recorders:
                name = recorder['name']
                if self.recorder_name and self.recorder_name != name:
                    continue
                recorder_info = recorder
            if not recorder_info:
                raise CriticalError('info for aws config recorder \'{}\' not found'.format(self.recorder_name))
            recording = recorder_info['recording']
            last_status = recorder_info['lastStatus']
            if not recording:
                self.critical()
            if last_status.upper() == 'PENDING':
                self.warning()
            elif last_status.upper() != 'SUCCESS':
                self.critical()
            self.msg = 'AWS config recorder \'{}\' recording: {}, lastStatus: {}'\
                       .format(self.recorder_name, recording, last_status)
        else:
            self.check_recorders(recorders)

    def check_recorders(self, recorder_list):
        num_recorders = len(recorder_list)
        num_recording = 0
        num_laststatus_success = 0
        for recorder in recorder_list:
            if recorder['recording']:
                num_recording += 1
            if recorder['lastStatus']:
                num_laststatus_success += 1
        if num_recorders < 1:
            self.warning()
        if num_recording != num_recorders:
            self.critical()
        elif num_laststatus_success != num_recorders:
            self.warning()
        self.msg = 'AWS config recorders recording: {}/{}'.format(num_recording, num_recorders)
        self.msg += ', lastStatus success: {}/{}'.format(num_laststatus_success, num_recorders)
        self.msg += ' |'
        self.msg += ' num_recorders={}'.format(num_recorders)
        self.msg += ' num_recording={};;{}'.format(num_recording, num_recorders)
        self.msg += ' num_laststatus_success={};{}'.format(num_laststatus_success, num_recorders)


if __name__ == '__main__':
    CheckAWSConfig().main()
