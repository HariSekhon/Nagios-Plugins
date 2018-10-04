#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: Tue Sep 26 09:24:25 CEST 2017
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

Nagios Plugin to check if a specific job / yarn application is running via the Yarn Resource Manager REST API

The --app name is a regex and the first matching job is checked

Optional additional checks:

- application is running as a specific --user
- application is running on a specific --queue
- application has a minimum number of running containers
- elapsed time - optional --warning / --critical thresholds apply
- if multiple applications match the given app name regex

Tested on HDP 2.6.1 and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import re
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, isInt, isList, validate_chars, validate_int, validate_regex
    from harisekhon.utils import ERRORS, CriticalError, UnknownError, jsonpp
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.7.3'


class CheckHadoopYarnAppRunning(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopYarnAppRunning, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Hadoop Yarn Resource Manager', 'Hadoop']
        self.path = '/ws/v1/cluster/apps'
        self.default_port = 8088
        self.json = True
        self.auth = False
        self.msg = 'Yarn Message Not Defined'
        self.app = None
        self.app_user = None
        self.queue = None
        self.min_containers = 0
        self.warn_on_dup_app = False
        self.limit = None
        self.list_apps = False

    def add_options(self):
        super(CheckHadoopYarnAppRunning, self).add_options()
        self.add_opt('-a', '--app', help='App / Job name to expect is running (case insensitive regex)')
        self.add_opt('-u', '--user', help='Expected user that yarn application should be running as (optional)')
        self.add_opt('-q', '--queue', help='Expected queue that yarn application should be running on (optional)')
        self.add_opt('-m', '--min-containers', metavar='N', default=0,
                     help='Expected minimum number of containers for application ' + \
                          '(optional, ignored on old Hadoop 2.2 where the runningContainers stat is not available)')
        self.add_opt('-n', '--limit', metavar='N', default=1000,
                     help='Limit number of results to search through (default: 1000)')
        self.add_opt('-d', '--warn-on-duplicate-app', action='store_true',
                     help='Warn when there is more than one matching application in the list (optional)')
        self.add_opt('-l', '--list-apps', action='store_true', help='List yarn apps and exit')
        self.add_thresholds()

    def process_options(self):
        super(CheckHadoopYarnAppRunning, self).process_options()

        self.app = self.get_opt('app')
        self.app_user = self.get_opt('user')
        self.queue = self.get_opt('queue')
        self.min_containers = self.get_opt('min_containers')
        self.limit = self.get_opt('limit')
        self.warn_on_dup_app = self.get_opt('warn_on_duplicate_app')
        self.list_apps = self.get_opt('list_apps')

        if not self.list_apps:
            if not self.app:
                self.usage('--app regex not defined')
            validate_regex(self.app, 'app')
        if self.app_user is not None:
            validate_chars(self.app_user, 'app user', r'\w')
        if self.queue is not None:
            validate_chars(self.queue, 'queue', r'\w-')
        if self.min_containers is not None:
            validate_int(self.min_containers, 'min containers', 0, None)
            self.min_containers = int(self.min_containers)

        self.limit = self.get_opt('limit')
        validate_int(self.limit, 'num results', 1, None)
        self.path += '?states=running&limit={0}'.format(self.limit)

        self.validate_thresholds(optional=True)

    def parse_json(self, json_data):
        apps = json_data['apps']
        if not apps:
            raise CriticalError('no Yarn apps running')
        app_list = apps['app']
        host_info = ''
        if self.verbose:
            host_info = " at '{0}:{1}'".format(self.host, self.port)
        if not isList(app_list):
            raise UnknownError("non-list returned for json_data[apps][app] by Yarn Resource Manager{0}"\
                               .format(host_info))
        num_apps = len(app_list)
        log.info("processing {0:d} running apps returned by Yarn Resource Manager{1}".format(num_apps, host_info))
        if num_apps > self.limit:
            raise UnknownError('num_apps {} > limit {}'.format(num_apps, self.limit))
        if self.list_apps:
            self.print_apps(app_list)
            sys.exit(ERRORS['UNKNOWN'])
        matched_app = None
        regex = re.compile(self.app, re.I)
        for app in app_list:
            if regex.search(app['name']):
                matched_app = app
                break
        if not matched_app:
            raise CriticalError("no app found with name matching '{app}' in list of last {limit} apps "\
                                .format(app=self.app, limit=self.limit) +
                                "returned by Yarn Resource Manager{host_info}".format(host_info=host_info))
        log.info('found matching app:\n\n%s\n', jsonpp(matched_app))
        elapsed_time = self.check_app(matched_app)
        if self.warn_on_dup_app:
            log.info('checking for duplicate apps matching the same regex')
            count = 0
            for app in app_list:
                if regex.match(app['name']):
                    count += 1
            if count > 1:
                self.msg += ', {0} DUPLICATE APPS WITH MATCHING NAMES DETECTED!'.format(count)
        self.msg += ' | app_elapsed_time={0}{1}'.format(elapsed_time, self.get_perf_thresholds())

    def check_app(self, app):
        state = app['state']
        user = app['user']
        queue = app['queue']
        # Hadoop 2.2 doesn't have this field
        running_containers = None
        if 'runningContainers' in app:
            running_containers = app['runningContainers']
            if not isInt(running_containers, allow_negative=True):
                raise UnknownError('running_containers {} is not an integer!'.format(running_containers))
            running_containers = int(running_containers)
        elapsed_time = app['elapsedTime']
        if not isInt(elapsed_time):
            raise UnknownError('elapsed time {} is not an integer'.format(elapsed_time))
        elapsed_time = int(elapsed_time / 1000)
        self.msg = "Yarn application '{0}' state = '{1}'".format(app['name'], state)
        if state != 'RUNNING':
            self.critical()
        ##################
        # This shouldn't be used any more now using more targeted query to only return running apps
        # state = FAILED / KILLED also gets final status = FAILED KILLED, no point double printing
        if state == 'FINISHED':
            self.msg += ", final status = '{0}'".format(app['finalStatus'])
        ##################
        self.msg += ", user = '{0}'".format(user)
        if self.app_user is not None and self.app_user != user:
            self.critical()
            self.msg += " (expected '{0}')".format(self.app_user)
        self.msg += ", queue = '{0}'".format(queue)
        if self.queue is not None and self.queue != queue:
            self.critical()
            self.msg += " (expected '{0}')".format(self.queue)
        if running_containers is not None:
            self.msg += ", running containers = {0}".format(running_containers)
            if self.min_containers is not None and running_containers < self.min_containers:
                self.critical()
                self.msg += " (< '{0}')".format(self.min_containers)
        self.msg += ", elapsed time = {0} secs".format(elapsed_time)
        self.check_thresholds(elapsed_time)
        return elapsed_time

    @staticmethod
    def print_apps(app_list):
        cols = {
            'Name': 'name',
            'State': 'state',
            'User': 'user',
            'Queue': 'queue',
            'Final Status': 'finalStatus',
            'Id': 'id',
        }
        widths = {}
        for col in cols:
            widths[col] = len(col)
        for app in app_list:
            for col in cols:
                if col not in widths:
                    widths[col] = 0
                width = len(str(app[cols[col]]))
                if width > widths[col]:
                    widths[col] = width
        total_width = 0
        columns = ('User', 'Queue', 'State', 'Final Status', 'Name', 'Id')
        for heading in columns:
            total_width += widths[heading] + 2
        print('=' * total_width)
        for heading in columns:
            print('{0:{1}}  '.format(heading, widths[heading]), end='')
        print()
        print('=' * total_width)
        for app in app_list:
            for col in columns:
                print('{0:{1}}  '.format(app[cols[col]], widths[col]), end='')
            print()


if __name__ == '__main__':
    CheckHadoopYarnAppRunning().main()
