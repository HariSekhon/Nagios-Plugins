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

Nagios Plugin to check the number of Jenkins jobs via the Rest API

Optional thresholds apply to the max number of configured jobs or range format for min/max

Can check the job count for only a given --view but it's a much less efficient O(n) operation because the code has to
manually return all of the view's jobs and count them on the client side rather than simply returning the figure as the
Jenkins API doesn't actually support a per view count

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
    from harisekhon.utils import log, ERRORS, CriticalError, jsonpp, validate_chars
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckJenkinsJobCount(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsJobCount, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Jenkins'
        self.default_port = 8080
        self.msg = self.name + ' job count '
        self.view = None
        self.list_views = False

    def add_options(self):
        super(CheckJenkinsJobCount, self).add_options()
        self.add_opt('-i', '--view', help='Restrict job counts to a specific view')
        self.add_opt('-l', '--list-views', action='store_true', help='List views and exit')
        self.add_thresholds()

    # can inherently accept AUTH token for password, see:
    # see https://wiki.jenkins-ci.org/display/JENKINS/Authenticating+scripted+clients
    # You can create an API token at:
    # http://jenkins/me/configure
    def process_options(self):
        super(CheckJenkinsJobCount, self).process_options()
        self.view = self.get_opt('view')
        self.list_views = self.get_opt('list_views')
        if self.view:
            validate_chars(self.view, 'view', r'A-Za-z0-9\s\.,_-')
        self.validate_thresholds(optional=True)

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
            if self.list_views:
                log.debug('getting views')
                views = server.get_views()
                if log.isEnabledFor(logging.DEBUG):
                    log.debug("%s", jsonpp(views))
                print('Jenkins views:\n')
                for view in views:
                    print(view['name'])
                sys.exit(ERRORS['UNKNOWN'])
            if self.view:
                log.debug('checking view exists')
                #assert server.view_exists(self.view)
                server.assert_view_exists(self.view)
                log.debug('getting jobs for view %s', self.view)
                view_jobs = server.get_jobs(view_name=self.view)
                if log.isEnabledFor(logging.DEBUG):
                    log.debug("%s", jsonpp(view_jobs))
                job_count = len(view_jobs)
            else:
                log.debug('getting job count')
                job_count = server.jobs_count()
                # more efficient with many folders
#               job_count = server.run_script(
#                "print(Hudson.instance.getAllItems("
#                "    hudson.model.AbstractProject).count{"
#                "        !(it instanceof hudson.matrix.MatrixConfiguration)"
#                "    })")
            query_time = time.time() - start_time
            log.debug('job count: %s', job_count)
            if self.view:
                self.msg += "for view '{0}' ".format(self.view)
            self.msg += '= {0}'.format(job_count)
            self.check_thresholds(job_count)
        except jenkins.JenkinsException as _:
            raise CriticalError(_)

        self.msg += ' | job_count={0:d}'.format(job_count)
        self.msg += self.get_perf_thresholds()
        self.msg += ' query_time={0:.4f}s'.format(query_time)


if __name__ == '__main__':
    CheckJenkinsJobCount().main()
