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

Nagios Plugin to check if a Jenkins job is set to buildable via the Rest API

The --password switch accepts either a password or an API token

Tested on Jenkins 2.60.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import RestNagiosPlugin
    from harisekhon.utils import validate_chars, ERRORS, UnknownError
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckJenkinsJob(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsJob, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Jenkins'
        self.default_port = 8080
        self.json = True
        self.msg = self.name + ' job '
        self.path = None
        self.job = None
        self.list_jobs = False
        self.age = None

    def add_options(self):
        super(CheckJenkinsJob, self).add_options()
        self.add_opt('-j', '--job', help='Job name to check')
        self.add_opt('-l', '--list', action='store_true', help='List jobs and exit')
        self.add_thresholds(default_warning=3600, default_critical=7200)

    def process_options(self):
        super(CheckJenkinsJob, self).process_options()
        self.job = self.get_opt('job')
        self.list_jobs = self.get_opt('list')
        if self.list_jobs:
            self.path = '/api/json'
        else:
            validate_chars(self.job, 'job', r'A-Za-z0-9\s\._-')
            self.path = '/job/{job}/api/json'.format(job=self.job)
            self.msg += "'{job}' is ".format(job=self.job)
        self.validate_thresholds(integer=False, optional=True)

    def parse_json(self, json_data):
        if self.list_jobs:
            print('Jenkins Jobs:\n')
            for job in json_data['jobs']:
                print(job['name'])
            sys.exit(ERRORS['UNKNOWN'])
        displayname = json_data['displayName']
        if displayname != self.job:
            raise UnknownError('displayname {} != job {}'.format(displayname, self.job))
        buildable = json_data['buildable']
        if not buildable:
            self.critical()
            self.msg += 'not '
        self.msg += 'buildable'


if __name__ == '__main__':
    CheckJenkinsJob().main()
