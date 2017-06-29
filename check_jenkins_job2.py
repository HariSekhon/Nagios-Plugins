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

Nagios Plugin to check the latest build of a Jenkins job via the Rest API

Optional --warning/--critical thresholds can be applied to last build duration
and --age can test the longest time since last build completion

The --password switch accepts either a password or an API token

Tested on Jenkins 2.60.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import time
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import RestNagiosPlugin
    from harisekhon.utils import validate_chars, validate_int, isInt
    from harisekhon.utils import WarningError, UnknownError, ERRORS, sec2human, support_msg_api
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
        self.add_opt('-a', '--age', help='Age in secs since last build (optional)')
        self.add_thresholds(default_warning=3600, default_critical=7200)

    def process_options(self):
        super(CheckJenkinsJob, self).process_options()
        self.job = self.get_opt('job')
        self.list_jobs = self.get_opt('list')
        self.age = self.get_opt('age')
        if self.list_jobs:
            self.path = '/api/json'
        else:
            validate_chars(self.job, 'job', r'A-Za-z0-9\s\._-')
            self.path = '/job/{job}/api/json'.format(job=self.job)
            self.msg += "'{job}' ".format(job=self.job)
        if self.age:
            validate_int(self.age, 'age')
            self.age = int(self.age)
        self.validate_thresholds(integer=False, optional=True)

    def parse_json(self, json_data):
        if self.list_jobs:
            print('Jenkins Jobs:\n')
            for job in json_data['jobs']:
                print(job['name'])
            sys.exit(ERRORS['UNKNOWN'])
        if 'lastCompletedBuild' in json_data:
            last_completed_build = json_data['lastCompletedBuild']
            if not last_completed_build:
                raise WarningError("job '{job}' not built yet".format(job=self.job))
            self.path = '/job/{job}/{number}/api/json'.format(job=self.job,
                                                              number=last_completed_build['number'])
            req = self.query()
            self.process_json(req.content)
            return
        displayname = json_data['displayName']
        duration = json_data['duration']
        if not isInt(duration):
            raise UnknownError('duration field returned non-integer! {0}'.format(support_msg_api()))
        duration = int(duration) / 1000
        result = json_data['result']
        timestamp = json_data['timestamp']
        if not isInt(timestamp):
            raise UnknownError('timestamp field returned non-integer! {0}'.format(support_msg_api()))
        timestamp = int(timestamp)
        building = json_data['building']
        self.msg += "build {build} status: ".format(build=displayname)
        if building:
            self.unknown()
            self.msg += 'STILL BUILDING!'
            return
        self.msg += result
        if result != 'SUCCESS':
            self.critical()
        self.msg += ', duration={duration} secs'.format(duration=duration)
        self.check_thresholds(duration)
        age = time.time() - (timestamp/1000)
        self.msg += ', age={age} secs'.format(age=sec2human(age))
        if age < 0:
            self.warning()
            self.msg += ' (< 0!)'
        if self.age and age > self.age:
            self.critical()
            self.msg += ' (> {0:d})'.format(self.age)
        self.msg += ' | build_duration={duration}s{perf_thresholds}'.format(duration=duration,
                                                                            perf_thresholds=self.get_perf_thresholds())


if __name__ == '__main__':
    CheckJenkinsJob().main()
