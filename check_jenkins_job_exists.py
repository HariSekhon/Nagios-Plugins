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

Nagios Plugin to check for the existence of a Jenkins job via the Rest API

This is a subset of the checks done in check_jenkins_job.py

The --password switch accepts either a password or an API token

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
    from harisekhon.utils import log, ERRORS, CriticalError, jsonpp
    from harisekhon.utils import validate_chars
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckJenkinsJobExists(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsJobExists, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Jenkins'
        self.default_port = 8080
        self.msg = self.name + ' job '
        self.job = None
        self.list_jobs = False

    def add_options(self):
        super(CheckJenkinsJobExists, self).add_options()
        self.add_opt('-j', '--job', help='Job name to check')
        self.add_opt('-l', '--list', action='store_true', help='List jobs and exit')

    # can inherently accept AUTH token for password, see:
    # see https://wiki.jenkins-ci.org/display/JENKINS/Authenticating+scripted+clients
    # You can create an API token at:
    # http://jenkins/me/configure
    def process_options(self):
        super(CheckJenkinsJobExists, self).process_options()
        self.job = self.get_opt('job')
        self.list_jobs = self.get_opt('list')
        if not self.list_jobs:
            validate_chars(self.job, 'job', r'A-Za-z0-9\s\._-')
            self.msg += "'{job}' ".format(job=self.job)

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
            if server.job_exists(self.job):
                self.msg += 'exists'
            else:
                self.critical()
                self.msg += 'does not exist!'
        except jenkins.JenkinsException as _:
            raise CriticalError(_)

        query_time = time.time() - start_time
        self.msg += ' | query_time={0:.4f}s'.format(query_time)


if __name__ == '__main__':
    CheckJenkinsJobExists().main()
