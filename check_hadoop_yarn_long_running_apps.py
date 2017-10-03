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

Nagios Plugin to detect too long running applications via the Yarn Resource Manager REST API

Useful for applying SLAs to Yarn jobs and detecting stale Spark Shells holding cluster resources

Thresholds --warning / --critical apply to application elapsed times in seconds and defaults to 12 hours
for warning (43220 secs) and 24 hours for critical (86400 secs) as this is a common use case that you
don't want daily jobs taking more than 1 day

Use the --include regex to check for only specific types of jobs eg. Spark Shell

Use the --exclude regex to exclude intentionally long running applications

Applications called llap\d+ are implicitly skipped

Tested on HDP 2.6.1 and Apache Hadoop 2.5.2, 2.6.4, 2.7.3

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
__version__ = '0.4.1'


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
        self.msg = 'Yarn Message Not Defined'
        self.include = None
        self.exclude = None
        self.implicitly_excluded = re.compile(r'^llap\d+$')
        self.limit = None
        self.list_apps = False

    def add_options(self):
        super(CheckHadoopYarnLongRunningApps, self).add_options()
        self.add_opt('-i', '--include', help='Include regex (anchored) to only check apps/jobs with matching names')
        self.add_opt('-e', '--exclude', help='Exclude regex (anchored) to exclude apps/jobs with matching names')
        self.add_opt('-n', '--limit', default=1000, help='Limit number of results to search through (default: 1000)')
        self.add_opt('-l', '--list-apps', action='store_true', help='List yarn apps and exit')
        self.add_thresholds()

    def process_options(self):
        super(CheckHadoopYarnLongRunningApps, self).process_options()

        self.include = self.get_opt('include')
        self.exclude = self.get_opt('exclude')
        self.limit = self.get_opt('limit')
        self.list_apps = self.get_opt('list_apps')

        if self.include is not None:
            validate_regex(self.include, 'include')
            self.include = re.compile('^' + self.include + '$')
        if self.exclude is not None:
            validate_regex(self.exclude, 'exclude')
            self.exclude = re.compile('^' + self.exclude + '$')

        self.limit = self.get_opt('limit')
        validate_int(self.limit, 'num results', 1, None)
        self.path += '?states=running&limit={0}'.format(self.limit)

        self.validate_thresholds(optional=True)

    def parse_json(self, json_data):
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
        self.check_app_elapsed_times(app_list)

    def check_app_elapsed_times(self, app_list):
        num_apps_breaching_sla = 0
        max_elapsed = 0
        matching_apps = 0
        max_threshold_msg = ''
        for app in app_list:
            name = app['name']
            queue = app['queue']
            if self.include is not None and not self.include.match(name):
                log.info("skipping app '%s' as doesn't match include regex", name)
                continue
            elif self.exclude is not None and self.exclude.match(name):
                log.info("skipping app '%s' by exclude regex", name)
                continue
            elif self.implicitly_excluded.match(name):
                log.info("skipping app '%s' by implicit exclude regex", name)
                continue
            # might want to actually check jobs on the llap queue aren't taking too long
            #elif queue == 'llap':
            #    log.info("skipping app '%s' on llap queue", name)
            #    continue
            matching_apps += 1
            elapsed_time = app['elapsedTime']
            assert isInt(elapsed_time)
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
        self.msg = 'Yarn apps breaching SLAs = {0}, checked {1} out of {2} running apps'\
                   .format(num_apps_breaching_sla, matching_apps, len(app_list)) + \
                   ', max elapsed app time = {0} secs{1}'\
                   .format(max_elapsed, max_threshold_msg)
        self.msg += ' | num_apps_breaching_SLA={0} max_elapsed_app_time={1}{2}'\
                    .format(num_apps_breaching_sla, max_elapsed, self.get_perf_thresholds())

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
                    assert isInt(val)
                    val = int(val / 1000)
                print('{0:{1}}  '.format(val, widths[col]), end='')
            print()


if __name__ == '__main__':
    CheckHadoopYarnLongRunningApps().main()
