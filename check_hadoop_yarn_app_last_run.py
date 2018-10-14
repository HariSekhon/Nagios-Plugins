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

Nagios Plugin to check the last completed run of a specific yarn application via the Yarn Resource Manager REST API

Useful for checking the latest state of a given batch job eg. Finished Success, Failed, Killed etc

Can optionally check the following additional aspects of the job:

- ran as a specific user
- ran on a specific queue
- did not exceed SLA times (--warning / --critical thresholds)

The --app name is a regex and the first matching job to is checked and optionally can apply --warn-on-duplicate
if multiple running jobs match the given regex

Spark - BEWARE: Spark jobs in Yarn Client mode always return SUCCEEDED in Yarn due to a Spark driver API limitation.
        This include Spark Shells. As a result you should always run Spark jobs in Yarn Cluster mode for reliable
        exit status that you can test from this program (it's also more resilient in case your local driver host fails)
        See https://issues.apache.org/jira/browse/SPARK-11058 for more details.

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
__version__ = '0.7.2'


class CheckHadoopYarnAppLastFinishedState(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopYarnAppLastFinishedState, self).__init__()
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
        super(CheckHadoopYarnAppLastFinishedState, self).add_options()
        self.add_opt('-a', '--app', help='App / Job name to expect is running (case insensitive regex)')
        self.add_opt('-u', '--user', help='Expected user that yarn application should have run as (optional)')
        self.add_opt('-q', '--queue', help='Expected queue that yarn application should have run on (optional)')
        self.add_opt('-n', '--limit', metavar='N', default=1000,
                     help='Limit number of results to search through (default: 1000)')
        self.add_opt('-d', '--warn-on-duplicate-app', action='store_true',
                     help='Warn when there is more than one matching application in the list (optional)')
        self.add_opt('-l', '--list-apps', action='store_true', help='List yarn apps and exit')
        self.add_thresholds()

    def process_options(self):
        super(CheckHadoopYarnAppLastFinishedState, self).process_options()

        self.app = self.get_opt('app')
        self.app_user = self.get_opt('user')
        self.queue = self.get_opt('queue')
        self.limit = self.get_opt('limit')
        self.warn_on_dup_app = self.get_opt('warn_on_duplicate_app')
        self.list_apps = self.get_opt('list_apps')

        if not self.list_apps:
            if not self.app:
                self.usage('--app name is not defined')
            validate_regex(self.app, 'app')
        if self.app_user is not None:
            validate_chars(self.app_user, 'app user', r'\w')
        if self.queue is not None:
            validate_chars(self.queue, 'queue', r'\w-')

        self.limit = self.get_opt('limit')
        validate_int(self.limit, 'num results', 1, None)
        # Not limited to states here in case we miss one, instead will return all and
        # then explicitly skip only RUNNING/ACCEPTED states
        self.path += '?limit={0}'.format(self.limit)

        self.validate_thresholds(optional=True)

    def parse_json(self, json_data):
        apps = json_data['apps']
        if not apps:
            raise CriticalError('no completed Yarn apps found')
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
            state = app['state']
            if state in ('RUNNING', 'ACCEPTED'):
                continue
            if regex.search(app['name']):
                matched_app = app
                break
        if not matched_app:
            raise CriticalError("no finished app/job found with name matching '{app}' in list of last {limit} apps "\
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
        elapsed_time = app['elapsedTime']
        if not isInt(elapsed_time):
            raise UnknownError('elapsed_time {} is not an integer!'.format(elapsed_time))
        elapsed_time = int(elapsed_time / 1000)
        self.msg = "Yarn application '{0}' state = '{1}'".format(app['name'], state)
#
#       Common States from > 10000 apps listed on production cluster:
#
#        ./check_hadoop_yarn_app_last_finished_state.py -a '.*' -l -n 20000000 | awk '{print $3" "$4}' | sort -u
#
#         state   final_status
#
#         FAILED FAILED
#         FINISHED FAILED
#         FINISHED KILLED
#         FINISHED SUCCEEDED
#         KILLED KILLED
#         RUNNING UNDEFINED
#
        # state = FAILED / KILLED get same final status = FAILED / KILLED, no point double printing
        # Hadoop 2.2 tests show FINISHING stage in tests
        if state in ('FINISHED', 'FINISHING'):
            final_status = app['finalStatus']
            self.msg += ", final status = '{0}'".format(final_status)
            if final_status != 'SUCCEEDED':
                self.critical()
        else:
            self.critical()
        self.msg += ", user = '{0}'".format(user)
        if self.app_user is not None and self.app_user != user:
            self.critical()
            self.msg += " (expected '{0}')".format(self.app_user)
        self.msg += ", queue = '{0}'".format(queue)
        if self.queue is not None and self.queue != queue:
            self.critical()
            self.msg += " (expected '{0}')".format(self.queue)
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
    CheckHadoopYarnAppLastFinishedState().main()
