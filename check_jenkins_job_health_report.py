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

Nagios Plugin to check the health report score of a Jenkins job via the Rest API

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
    from harisekhon.utils import validate_chars, isFloat
    from harisekhon.utils import ERRORS, UnknownError
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckJenkinsJobHealthReport(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsJobHealthReport, self).__init__()
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
        super(CheckJenkinsJobHealthReport, self).add_options()
        self.add_opt('-j', '--job', help='Job name to check')
        self.add_opt('-l', '--list', action='store_true', help='List jobs and exit')
        self.add_thresholds(default_warning=80, default_critical=60, percent=True)

    def process_options(self):
        super(CheckJenkinsJobHealthReport, self).process_options()
        self.job = self.get_opt('job')
        self.list_jobs = self.get_opt('list')
        if not self.list_jobs:
            validate_chars(self.job, 'job', r'A-Za-z0-9\s\._-')
            self.path = '/job/{job}/api/json'.format(job=self.job)
        self.validate_thresholds(percent=True, simple='lower')

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
        health_report = json_data['healthReport']
        if not health_report:
            raise UnknownError("no health report found for job '{job}' (not built yet?)".format(job=self.job))
        health_report = health_report[0]
        score = health_report['score']
        if not isFloat(score):
            raise UnknownError("non-numeric score returned in health report for job '{job}'".format(job=self.job))
        score = float(score)
        description = health_report['description']
        self.msg += "'{job}' health report score = {score}".format(job=self.job, score=score)
        self.check_thresholds(score)
        #self.msg += ", description: '{description}'".format(description=description)
        self.msg += ", {description}".format(description=description)
        self.msg += ' | health_report_score={score}%{thresholds}'\
                    .format(score=score, thresholds=self.get_perf_thresholds(boundary='lower'))


if __name__ == '__main__':
    CheckJenkinsJobHealthReport().main()
