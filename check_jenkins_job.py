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

Nagios Plugin to check the latest build status of a Jenkins job via the Rest API

Optional --warning/--critical thresholds can be applied to last build duration
and --age can test the longest time since last build completion

The --password switch accepts either a password or a Jenkins API token

Tested on Jenkins 2.60.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
import os
import sys
import time
import traceback
try:
    import jenkins
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, ERRORS, WarningError, CriticalError, UnknownError, sec2human, jsonpp
    from harisekhon.utils import validate_chars, validate_int, isInt, support_msg_api
    from harisekhon import RestNagiosPlugin
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
        self.msg = self.name + ' job '
        self.job = None
        self.list_jobs = False
        self.age = None

    def add_options(self):
        super(CheckJenkinsJob, self).add_options()
        self.add_opt('-j', '--job', help='Job name to check')
        self.add_opt('-l', '--list', action='store_true', help='List jobs and exit')
        self.add_opt('-a', '--age', help='Age in secs since last build (optional)')
        self.add_thresholds(default_warning=3600, default_critical=7200)

    # can inherently accept AUTH token for password, see:
    # see https://wiki.jenkins-ci.org/display/JENKINS/Authenticating+scripted+clients
    # You can create an API token at:
    # http://jenkins/me/configure
    def process_options(self):
        super(CheckJenkinsJob, self).process_options()
        self.job = self.get_opt('job')
        self.list_jobs = self.get_opt('list')
        if not self.list_jobs:
            validate_chars(self.job, 'job', r'A-Za-z0-9\s\._-')
            self.msg += "'{job}' ".format(job=self.job)
        self.age = self.get_opt('age')
        if self.age:
            validate_int(self.age, 'age')
            self.age = int(self.age)
        self.validate_thresholds(integer=False, optional=True)

    def run(self):
        server_url = '{proto}://{host}:{port}'.format(proto=self.protocol, host=self.host, port=self.port)
        try:
            log.debug('setting up Jenkins connection to %s', server_url)
            start_time = time.time()
            server = jenkins.Jenkins(server_url, username=self.user, password=self.password, timeout=self.timeout / 3)
            if log.isEnabledFor(logging.DEBUG):
                log.debug('getting user')
                user = server.get_whoami()
                log.debug('connected as user %s', jsonpp(user))
                #log.debug('getting version')
                # bug - https://bugs.launchpad.net/python-jenkins/+bug/1578626
                #version = server.get_version()
                #log.debug('Jenkins server version is %s', version)
            if self.list_jobs:
                log.debug('getting jobs')
                #jobs = server.get_jobs()
                # recursively get all jobs
                jobs = server.get_all_jobs()
                # more efficient with many folders
#                jobs = server.run_script("""
#                    import groovy.json.JsonBuilder;
#
#                    // get all projects excluding matrix configuration
#                    // as they are simply part of a matrix project.
#                    // there may be better ways to get just jobs
#                    items = Jenkins.instance.getAllItems(AbstractProject);
#                    items.removeAll {
#                      it instanceof hudson.matrix.MatrixConfiguration
#                    };
#
#                    def json = new JsonBuilder()
#                    def root = json {
#                      jobs items.collect {
#                        [
#                          name: it.name,
#                          url: Jenkins.instance.getRootUrl() + it.getUrl(),
#                          color: it.getIconColor().toString(),
#                          fullname: it.getFullName()
#                        ]
#                      }
#                    }
#
#                    // use json.toPrettyString() if viewing
#                    println json.toString()
#                    """)
                print('Jenkins Jobs:\n')
                for job in jobs:
                    print(job['fullname'])
                sys.exit(ERRORS['UNKNOWN'])

            log.debug('checking job exists')
            # less informative error message
            #assert server.job_exists(self.job) # True
            # this will give an intuitive error that a job doesn't exist
            # rather than letting it fail later with 'request object not found'
            server.assert_job_exists(self.job)

            log.debug('getting last build num for job %s', self.job)
            last_completed_build = server.get_job_info(self.job)['lastCompletedBuild']
            if not last_completed_build:
                raise WarningError("job '{job}' not built yet".format(job=self.job))
            latest_build = last_completed_build['number']
            log.debug('getting build info for job %s, latest build num %s', self.job, latest_build)
            build_info = server.get_build_info(self.job, latest_build)
            log.debug('build info: %s', build_info)
            self.process_build_info(build_info)
        except jenkins.JenkinsException as _:
            raise CriticalError(_)

        query_time = time.time() - start_time
        self.msg += ' query_time={0:.4f}s'.format(query_time)

    def process_build_info(self, build_info):
        displayname = build_info['displayName']
        duration = build_info['duration']
        if not isInt(duration):
            raise UnknownError('duration field returned non-integer! {0}'.format(support_msg_api()))
        duration = int(duration) / 1000
        result = build_info['result']
        timestamp = build_info['timestamp']
        if not isInt(timestamp):
            raise UnknownError('timestamp field returned non-integer! {0}'.format(support_msg_api()))
        timestamp = int(timestamp)
        building = build_info['building']
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
        self.msg += ' | build_duration={duration}s{perf_thresholds}'.format(duration=duration, \
                                                                     perf_thresholds=self.get_perf_thresholds())


if __name__ == '__main__':
    CheckJenkinsJob().main()
