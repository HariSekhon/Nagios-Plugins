#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-10-20 19:15:30 +0200 (Fri, 20 Oct 2017)
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

Nagios Plugin to check Presto queries on a cluster via the Coordinator API

Checks:

    - running queries (including planning, starting and finishing states)
            or
    - failed queries
            or
    - blocked queries
            or
    - queued queries

    - checks warning / critical thresholds against resulting count
    - limits to testing queries out of last N [matching] total queries
      (to avoid persistent critical state for historical query failures)
    - checks minimum number of queries found of all types
      (eg. raises warning if there were no queries found at all of any result)
    - optionally check only certain SQL queries matching include and / or exclude regex
      against the actual SQL queries

This is useful to be able to determine if there are failed Presto jobs or queries especially of
a certain type or accessing a specific resource, eg. against a certain Presto catalog / external system

Warning / Critical thresholds apply to the number of running / failed / blocked / queued queries and it also outputs
graph perfdata of the number of recently running / failed / blocked / queued queries
as well as query time to retrieve this information

Will get a '404 Not Found' if you try to run it against a Presto Worker as this information
is only available via the Presto Coordinator API

Tested on:

- Presto Facebook versions:               0.152, 0.157, 0.167, 0.179, 0.185, 0.186, 0.187, 0.188, 0.189
- Presto Teradata distribution versions:  0.152, 0.157, 0.167, 0.179
- back tested against all Facebook Presto releases 0.69, 0.71 - 0.189
  (see Presto docker images on DockerHub at https://hub.docker.com/u/harisekhon)

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

from collections import OrderedDict
import logging
import os
import re
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, ERRORS, UnknownError, support_msg_api, isList, validate_regex, validate_int
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.7.0'


class CheckPrestoQueries(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPrestoQueries, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Presto Coordinator', 'Presto']
        self.default_port = 8080
        self.auth = False
        self.json = True
        self.path = '/v1/query'
        self.msg = 'Presto msg not defined'
        self.include = None
        self.exclude = None
        self.num = None
        self.min_queries = None
        self.list = False
        self.state_selector = None

    def add_options(self):
        super(CheckPrestoQueries, self).add_options()
        self.add_opt('-i', '--include', metavar='regex', help='Include regex for queries to check')
        self.add_opt('-e', '--exclude', metavar='regex', help='Exclude regex for queries to exclude' + \
                                                              ' (takes priority over --include')
        self.add_opt('-r', '--running', action='store_true',
                     help='Select running queries (includes planning, starting and finishing)')
        self.add_opt('-f', '--failed', action='store_true', help='Select failed queries')
        self.add_opt('-b', '--blocked', action='store_true', help='Select blocked queries')
        self.add_opt('-q', '--queued', action='store_true', help='Select queued queries')
        self.add_opt('-n', '--num', metavar='N', default=100,
                     help="Check only the last N matching queries to ensure older errors don't keep alerting" + \
                          " (default: 100)")
        self.add_opt('-m', '--min-queries', metavar='N', default=1,
                     help='Minimum number of matching queries to expect to find' + \
                          ', raises warning if below this number (default: 1)')
        self.add_opt('-l', '--list', action='store_true', help='List queries and exit')
        self.add_thresholds(default_warning=0, default_critical=20)

    def process_options(self):
        super(CheckPrestoQueries, self).process_options()
        # Possible Query States - https://prestodb.io/docs/current/admin/web-interface.html
        self.list = self.get_opt('list')
        if not self.list:
            if self.get_opt('running'):
                self.state_selector = ['RUNNING', 'PLANNING', 'STARTING', 'FINISHING']
            if self.get_opt('failed'):
                if self.state_selector is not None:
                    self.usage('cannot specify more than one of --running / --failed / --blocked / --queued at a time')
                self.state_selector = ['FAILED']
            if self.get_opt('blocked'):
                if self.state_selector is not None:
                    self.usage('cannot specify more than one of --running / --failed / --blocked / --queued at a time')
                self.state_selector = ['BLOCKED']
            if self.get_opt('queued'):
                if self.state_selector is not None:
                    self.usage('cannot specify more than one of --running / --failed / --blocked / --queued at a time')
                self.state_selector = ['QUEUED']
            if self.state_selector is None:
                self.usage('must specify one type of --running / --failed / --blocked / --queued queries')
        self.include = self.get_opt('include')
        self.exclude = self.get_opt('exclude')
        if self.include:
            validate_regex(self.include, 'include')
            self.include = re.compile(self.include, re.I)
        if self.exclude:
            validate_regex(self.exclude, 'exclude')
            self.exclude = re.compile(self.exclude, re.I)
        self.num = self.get_opt('num')
        validate_int(self.num, 'num', 0)
        self.num = int(self.num)
        self.min_queries = self.get_opt('min_queries')
        validate_int(self.min_queries, 'minimum queries', 0)
        self.min_queries = int(self.min_queries)
        self.validate_thresholds()

    def get_field(self, json_data, index):
        subfield = None
        if '.' in index:
            (index, subfield) = index.split('.', 1)
        if index == 'errorCode':
            if index not in json_data:
                return ''
        if index in json_data:
            field = json_data[index]
        else:
            return 'N/A'
        if subfield:
            field = self.get_field(field, subfield)
        return field

    def list_queries(self, query_list):
        max_query_display_width = 100
        print('Presto SQL Queries:\n')
        cols = OrderedDict([
            ('User', 'session.user'),
            ('State', 'state'),
            ('Error code', 'errorCode.code'),
            ('Error name', 'errorCode.name'),
            ('Error type', 'errorCode.type'),
            ('Memory Pool', 'memoryPool'),
            ('Query', 'query'),
        ])
        widths = {}
        for col in cols:
            widths[col] = len(col)
        for query_item in query_list:
            for col in cols:
                if col not in widths:
                    widths[col] = 0
                val = self.get_field(query_item, cols[col])
                width = min(max_query_display_width, len(str(val).strip()))
                if width > widths[col]:
                    widths[col] = width
        total_width = 0
        for heading in cols:
            total_width += widths[heading] + 2
        # ends up being 2 chars longer than items, but if queries are long and result in trailing ...
        # then make sure this lines up with headers by adding one
        total_width += 1
        print('=' * total_width)
        for heading in cols:
            print('{0:{1}}  '.format(heading, widths[heading]), end='')
        print()
        print('=' * total_width)
        re_collapse_lines = re.compile(r'\s*\n\s*')
        for query_item in query_list:
            for col in cols:
                val = self.get_field(query_item, cols[col])
                val = re_collapse_lines.sub(' ', str(val).strip())
                trailing = ''
                if len(val) > max_query_display_width:
                    trailing = '...'
                print('{0:{1}}{2}  '.format(val[:max_query_display_width], widths[col], trailing), end='')
            print()
        sys.exit(ERRORS['UNKNOWN'])

    def parse_json(self, json_data):
        if not isList(json_data):
            raise UnknownError('non-list returned by Presto for queries. {0}'.format(support_msg_api()))
        matching_queries = []
        for query_item in json_data:
            query = query_item['query']
            log.info('query: %s', query)
            if self.exclude and self.exclude.search(query):
                log.info("excluding query '%s'", query)
                continue
            if self.include:
                if not self.include.search(query):
                    continue
                log.info("including query: %s", query)
            matching_queries.append(query_item)
        num_matching_queries = len(matching_queries)
        # limit searching to last --num queries
        if num_matching_queries < self.num:
            log.info('number of matching queries %d is less than query limit of %d', num_matching_queries, self.num)
            self.num = num_matching_queries
        last_n_matching_queries = matching_queries[0:self.num]
        if self.list:
            self.list_queries(last_n_matching_queries)
        selected_queries = [query_item for query_item in last_n_matching_queries \
                            if query_item['state'] in self.state_selector]
        if log.isEnabledFor(logging.INFO):
            for query_item in matching_queries:
                log.info('%s query found: %s', self.state_selector, query_item['query'])
        num_selected_queries = len(selected_queries)
        self.msg = 'Presto SQL - {0} {1} queries'.format(num_selected_queries, self.state_selector[0].lower())
        self.check_thresholds(num_selected_queries)
        self.msg += ' out of last {0}'.format(num_matching_queries)
        if self.include or self.exclude:
            self.msg += ' matching'
        self.msg += ' queries'
        if num_matching_queries < self.min_queries:
            self.warning()
            self.msg += ' (< {0})'.format(self.min_queries)
        self.msg += ' on coordinator'
        if self.verbose:
            self.msg += ' {0}:{1}'.format(self.host, self.port)
        self.msg += ' | num_{0}_queries={1}{2} num_matching_queries={3}:{4}'\
                    .format(self.state_selector[0].lower(),
                            num_selected_queries,
                            self.get_perf_thresholds(),
                            num_matching_queries,
                            self.min_queries)


if __name__ == '__main__':
    CheckPrestoQueries().main()
