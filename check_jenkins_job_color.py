#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2013-11-13 13:52:54 +0000 (Wed, 13 Nov 2013)
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

Nagios Plugin to check the status color of a Jenkins job via the Rest API

This is a simpler yes/no type check than check_jenkins_job.py / check_jenkins_job2.py

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
    from harisekhon.utils import validate_chars
    from harisekhon.utils import ERRORS
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckJenkinsJobColor(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsJobColor, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Jenkins'
        self.default_port = 8080
        self.json = True
        self.msg = self.name + ' job '
        self.path = '/api/json'
        self.job = None
        self.list_jobs = False

    def add_options(self):
        super(CheckJenkinsJobColor, self).add_options()
        self.add_opt('-j', '--job', help='Job name to check')
        self.add_opt('-l', '--list', action='store_true', help='List jobs and exit')

    def process_options(self):
        super(CheckJenkinsJobColor, self).process_options()
        self.job = self.get_opt('job')
        self.list_jobs = self.get_opt('list')
        if not self.list_jobs:
            validate_chars(self.job, 'job', r'A-Za-z0-9\s\._-')
            self.path = '/job/{job}/api/json'.format(job=self.job)

    def parse_json(self, json_data):
        if self.list_jobs:
            jobs = json_data['jobs']
            print('Jenkins Jobs:\n')
            for job in jobs:
                print(job['name'])
            sys.exit(ERRORS['UNKNOWN'])
        # this method has a nicer job not found error message
        # but it's less efficient if querying a Jenkins server with lots of jobs
        #job = None
        #for _ in jobs:
        #    if _['name'].lower() == self.job.lower():
        #        job = _
        #        break
        #if not job:
        #    raise CriticalError("job '{job}' not found. See --list to see available jobs".format(job=self.job))
        #color = job['color']
        color = json_data['color']
        self.msg += "'{job}' status color = '{color}'".format(job=self.job, color=color)
        if color in ('blue', 'green'):
            pass
        elif color == 'notbuilt':
            self.warning()
        else:
            self.critical()


if __name__ == '__main__':
    CheckJenkinsJobColor().main()
