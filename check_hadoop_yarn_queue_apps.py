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

Nagios Plugin to check only expected apps are running on a Yarn queue via the Yarn Resource Manager REST API

Useful for checking only the right jobs are running on a queue, validates the names of all running apps on the
given queue against allowed and / or disallowed regexes. If disallowed is given, it takes priority and raises WARNING
if any apps are found with names matching the disallowed regex. If allow is specified then raises WARNING if any apps
are detected on the yarn queue with names that do not match the allow regex.

You can use this to make sure Spark Shells aren't running on your production Yarn queues (checks all queues with the
regex word 'production' anywhere in them), eg.

./check_hadoop_yarn_queue_apps.py --queue production --disallow 'Spark.*Shell'

In normal mode prints the totals of disallowed, non-allowed (not matching --allow if specified) and allowed (not
failing either --disallow or --allow regexes). In Verbose mode if there is more than one matching queue then
will also output stats per queue (be careful using this as if you're changing the number of matching queues over
time it could result in more perfdata fields which can break PNP4Nagios graphs)

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
    from harisekhon.utils import log, isInt, isList, validate_int, validate_regex, plural
    from harisekhon.utils import ERRORS, UnknownError
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4.1'


class CheckHadoopYarnQueueApps(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopYarnQueueApps, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Hadoop Yarn Resource Manager', 'Hadoop']
        self.path = '/ws/v1/cluster/apps'
        self.default_port = 8088
        self.json = True
        self.auth = False
        self.msg = 'Yarn apps running with '
        self.allow = None
        self.disallow = None
        self.queue = None
        self.limit = None
        self.list_apps = False

    def add_options(self):
        super(CheckHadoopYarnQueueApps, self).add_options()
        self.add_opt('-q', '--queue', default='default',
                     help='Check apps/jobs on queues matching this given regex (default: \'default\' queue)')
        self.add_opt('-a', '--allow', metavar='NAME',
                     help='Expect only apps with names matching this regex (optional)')
        self.add_opt('-d', '--disallow', metavar='NAME',
                     help='Blacklist any apps with names matching this regex, eg. \'Spark.*Shell\' (optional)')
        self.add_opt('-n', '--limit', default=1000, help='Limit number of results to search through (default: 1000)')
        self.add_opt('-l', '--list-apps', action='store_true', help='List yarn apps and exit')

    def process_options(self):
        super(CheckHadoopYarnQueueApps, self).process_options()

        self.allow = self.get_opt('allow')
        self.disallow = self.get_opt('disallow')
        self.limit = self.get_opt('limit')
        self.list_apps = self.get_opt('list_apps')

        if self.allow is not None:
            validate_regex(self.allow, 'allow')
            self.allow = re.compile(self.allow, re.I)
        if self.disallow is not None:
            validate_regex(self.disallow, 'disallow')
            self.disallow = re.compile(self.disallow, re.I)

        queue = self.get_opt('queue')
        validate_regex(queue, 'queue')
        self.queue = re.compile(queue, re.I)

        self.limit = self.get_opt('limit')
        validate_int(self.limit, 'num results', 1, None)
        self.path += '?states=running&limit={0}'.format(self.limit)

    def parse_json(self, json_data):
        app_list = self.get_app_list(json_data)
        self.check_queue_apps(app_list)

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
        if not self.queue.search(queue):
            log.info("skipping app '%s' as it is running on queue '%s', does not match queue regex", name, queue)
            return False
        log.info("processing app '%s' running on matching queue '%s'", name, queue)
        return True

    def check_queue_apps(self, app_list):
        queue_stats = {'allowed': {'total': 0},
                       'disallowed': {'total': 0},
                       'non-allowed':{'total': 0}}
        matching_apps = 0
        for app in app_list:
            if not self.app_selector(app):
                continue
            name = app['name']
            queue = app['queue']
            matching_apps += 1
            if self.disallow is not None and self.disallow.search(name):
                self.warning()
                log.debug("app '%s' on queue '%s' disallowed by regex", name, queue)
                queue_stats['disallowed']['total'] += 1
                queue_stats['disallowed'][queue] = queue_stats['disallowed'].get(queue, 0) + 1
            elif self.allow is not None and not self.allow.search(name):
                self.warning()
                log.debug("app '%s' on queue '%s' failed to match allow by regex", name, queue)
                queue_stats['non-allowed']['total'] += 1
                queue_stats['non-allowed'][queue] = queue_stats['non-allowed'].get(queue, 0) + 1
            else:
                log.debug("app '%s' on queue '%s' allowed", name, queue)
                queue_stats['allowed']['total'] += 1
                queue_stats['allowed'][queue] = queue_stats['allowed'].get(queue, 0) + 1
        self.msg_queue_stats(queue_stats)

    def msg_queue_stats(self, queue_stats):
        matching_queues = len(queue_stats['allowed']) + \
                          len(queue_stats['non-allowed']) + \
                          len(queue_stats['disallowed']) - 3  # account for 'total' in each dict
        self.msg += "{0} matching queue{1}".format(matching_queues, plural(matching_queues))
        for _type in ('disallowed', 'non-allowed', 'allowed'):
            self.msg += ', {0} = {1}'.format(_type, queue_stats[_type]['total'])
        if self.verbose and matching_queues > 1:
            for queue in sorted(list(set(queue_stats['disallowed'].keys() +
                                         queue_stats['non-allowed'].keys() +
                                         queue_stats['allowed'].keys()))):
                if queue == 'total':
                    continue
                for _type in ('disallowed', 'non-allowed', 'allowed'):
                    self.msg += ', {0} {1} = {2}'.format(queue, _type, queue_stats[_type].get(queue, 0))
        self.msg += ' |'
        for _type in ('disallowed', 'non-allowed', 'allowed'):
            self.msg += " '{0}'={1}".format(_type, queue_stats[_type]['total'])
        if self.verbose and matching_queues > 1:
            for queue in sorted(list(set(queue_stats['disallowed'].keys() +
                                         queue_stats['non-allowed'].keys() +
                                         queue_stats['allowed'].keys()))):
                if queue == 'total':
                    continue
                for _type in ('disallowed', 'non-allowed', 'allowed'):
                    self.msg += " '{0} {1}'={2}".format(queue, _type, queue_stats[_type].get(queue, 0))
        return queue_stats

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
                        raise UnknownError('elapsed time {} is not an integer'.format(val))
                    val = int(val / 1000)
                print('{0:{1}}  '.format(val, widths[col]), end='')
            print()


if __name__ == '__main__':
    CheckHadoopYarnQueueApps().main()
