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

r"""

Nagios Plugin to detect too long running applications via the Yarn Resource Manager REST API

Useful for applying SLAs to Yarn jobs and detecting stale Spark Shells holding cluster resources

Thresholds --warning / --critical apply to application elapsed times in seconds and defaults to 12 hours
for warning (43220 secs) and 24 hours for critical (86400 secs) as this is a common use case that you
don't want daily jobs taking more than 1 day

Use the --include regex to check for only specific types of jobs eg. Spark Shell

Use the --exclude regex to exclude intentionally long running applications

Applications called llap\d+ are implicitly skipped

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
    from harisekhon.utils import log, isInt, isList, validate_int, validate_regex
    from harisekhon.utils import ERRORS, UnknownError
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.8.2'


class CheckHadoopYarnLongRunningApps(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopYarnLongRunningApps, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Hadoop Yarn Resource Manager', 'Hadoop']
        self.path = '/ws/v1/cluster/apps'
        self.default_port = 8088
        self.json = True
        self.auth = False
        self.msg = 'Yarn apps breaching SLAs = '
        self.include = None
        self.exclude = None
        self.implicitly_excluded = re.compile(r'^llap\d+$')
        self.queue = None
        self.exclude_queue = None
        self.limit = None
        self.list_apps = False

    def add_options(self):
        super(CheckHadoopYarnLongRunningApps, self).add_options()
        self.add_opt('-i', '--include', help='Only check apps/jobs with names matching this regex (optional)')
        self.add_opt('-e', '--exclude', help='Exclude apps/jobs with names matching this regex (optional)')
        self.add_opt('-q', '--queue', help='Only check apps/jobs on queues matching this given regex (optional)')
        self.add_opt('--exclude-queue', default='^llap$',
                     help='Exclude apps/jobs on queues matching this given regex ' +
                     '(optional, set blank to disable, default: ^llap$)')
        self.add_opt('-n', '--limit', default=1000, help='Limit number of results to search through (default: 1000)')
        self.add_opt('-l', '--list-apps', action='store_true', help='List yarn apps and exit')
        self.add_thresholds(default_warning=43220, default_critical=86400)

    def process_options(self):
        super(CheckHadoopYarnLongRunningApps, self).process_options()

        self.include = self.get_opt('include')
        self.exclude = self.get_opt('exclude')
        self.process_options_common()

    def process_options_common(self):
        self.limit = self.get_opt('limit')
        self.list_apps = self.get_opt('list_apps')

        if self.include is not None:
            validate_regex(self.include, 'include')
            self.include = re.compile(self.include, re.I)
        if self.exclude is not None:
            validate_regex(self.exclude, 'exclude')
            self.exclude = re.compile(self.exclude, re.I)

        queue = self.get_opt('queue')
        if queue:
            validate_regex(queue, 'queue')
            self.queue = re.compile(queue, re.I)

        exclude_queue = self.get_opt('exclude_queue')
        if exclude_queue:
            validate_regex(exclude_queue, 'exclude queue')
            self.exclude_queue = re.compile(exclude_queue, re.I)

        self.limit = self.get_opt('limit')
        validate_int(self.limit, 'num results', 1, None)
        self.path += '?states=running&limit={0}'.format(self.limit)

        self.validate_thresholds(optional=True)

    def parse_json(self, json_data):
        app_list = self.get_app_list(json_data)
        (num_apps_breaching_sla, matching_apps, max_elapsed, max_threshold_msg) = self.check_app_elapsed_times(app_list)
        self.msg += '{0}, checked {1} out of {2} running apps'\
                   .format(num_apps_breaching_sla, matching_apps, len(app_list)) + \
                   ', max elapsed app time = {0} secs{1}'\
                   .format(max_elapsed, max_threshold_msg)
        self.msg += ' | num_apps_breaching_SLA={0} max_elapsed_app_time={1}{2}'\
                    .format(num_apps_breaching_sla, max_elapsed, self.get_perf_thresholds())

    def get_app_list(self, json_data):
        apps = json_data['apps']
        app_list = []
        if apps:
            app_list = apps['app']
        host_info = ''
        if self.verbose:
            host_info = " at '{0}:{1}'".format(self.host, self.port)
        if not isList(app_list):
            raise UnknownError("non-list returned for json_data[apps][app] by Yarn Resource Manager{0}"\
                               .format(host_info))
        num_apps = len(app_list)
        log.info("processing {0:d} apps returned by Yarn Resource Manager{1}".format(num_apps, host_info))
        if self.list_apps:
            self.print_apps(app_list)
            sys.exit(ERRORS['UNKNOWN'])
        return app_list

    def app_selector(self, app):
        name = app['name']
        queue = app['queue']
        if self.include is not None and not self.include.search(name):
            log.info("skipping app '%s' as doesn't match include regex", name)
            return False
        elif self.exclude is not None and self.exclude.search(name):
            log.info("skipping app '%s' by exclude regex", name)
            return False
        elif self.implicitly_excluded.search(name):
            log.info("skipping app '%s' by implicit exclude regex", name)
            return False
        elif self.queue is not None and not self.queue.search(queue):
            log.info("skipping app '%s' as it is running on queue '%s', does not match queue regex", name, queue)
            return False
        elif self.exclude_queue is not None and self.exclude_queue.search(queue):
            log.info("skipping app '%s' as it is running on queue '%s' which matches queue exclude regex", name, queue)
            return False
        return True

    def check_app_elapsed_times(self, app_list):
        num_apps_breaching_sla = 0
        max_elapsed = 0
        matching_apps = 0
        max_threshold_msg = ''
        # save msg as check_thresholds appends to it which we want to reset in this case
        msg = self.msg
        for app in app_list:
            if not self.app_selector(app):
                continue
            name = app['name']
            matching_apps += 1
            elapsed_time = app['elapsedTime']
            if not isInt(elapsed_time):
                raise UnknownError('elapsed_time {} is not an integer!'.format(elapsed_time))
            elapsed_time = int(elapsed_time / 1000)
            threshold_msg = self.check_thresholds(elapsed_time)
            if threshold_msg:
                num_apps_breaching_sla += 1
                log.info("app '%s' is breaching SLA", name)
            if elapsed_time > max_elapsed:
                max_elapsed = elapsed_time
                max_threshold_msg = threshold_msg
        if max_threshold_msg:
            max_threshold_msg = ' ' + max_threshold_msg
        # restore msg prefix as check_thresholds appends every threshold breach
        self.msg = msg
        return (num_apps_breaching_sla, matching_apps, max_elapsed, max_threshold_msg)

    @staticmethod
    def print_apps(app_list):
        cols = {
            'Name': 'name',
            'State': 'state',
            'User': 'user',
            'Queue': 'queue',
            'Final Status': 'finalStatus',
            'Elapsed Time': 'elapsedTime',
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
        columns = ('User', 'Queue', 'State', 'Final Status', 'Elapsed Time', 'Name', 'Id')
        for heading in columns:
            total_width += widths[heading] + 2
        print('=' * total_width)
        for heading in columns:
            print('{0:{1}}  '.format(heading, widths[heading]), end='')
        print()
        print('=' * total_width)
        for app in app_list:
            for col in columns:
                val = app[cols[col]]
                if col == 'Elapsed Time':
                    if not isInt(val):
                        raise UnknownError('Elapsed Time {} is not an integer!'.format(val))
                    val = int(val / 1000)
                print('{0:{1}}  '.format(val, widths[col]), end='')
            print()


if __name__ == '__main__':
    CheckHadoopYarnLongRunningApps().main()
