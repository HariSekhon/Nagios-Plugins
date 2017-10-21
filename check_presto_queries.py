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

    - failed queries vs warning / critical thresholds out of last N [matching] queries
    - minimum number of [matching] queries (raises warning)
    - optionally check only certain SQL queries matching include and / or exclude regex
      against the actual SQL queries

This is useful to be able to determine if there are failed Presto jobs or queries especially of
a certain type or accessing a specific resource, eg. against a certain Presto catalog / external system

Warning / Critical thresholds apply to the number of failed queries and it also outputs
graph perfdata of the number of recently failed queries as well as query time to retrieve this information

Will get a '404 Not Found' if you try to run it against a Presto Worker as this information
is only available via the Presto Coordinator API

Tested on:

- Presto Facebook version 0.185
- Presto Teradata distribution versions 0.167, 0.179

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

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
    from harisekhon.utils import log, UnknownError, support_msg_api, isList, validate_regex, validate_int
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


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

    def add_options(self):
        super(CheckPrestoQueries, self).add_options()
        self.add_opt('-i', '--include', metavar='regex', help='Include regex for queries to check')
        self.add_opt('-e', '--exclude', metavar='regex', help='Exclude regex for queries to exclude' + \
                                                              ' (takes priority over --include')
        self.add_opt('-n', '--num', metavar='N', default=100,
                     help="Check only the last N matching queries to ensure older errors don't keep alerting" + \
                          " (default: 100)")
        self.add_opt('-m', '--min-queries', metavar='N', default=1,
                     help='Minimum number of matching queries to expect to find' + \
                          ', raises warning if below this number (default: 1)')
        self.add_thresholds(default_warning=0, default_critical=20)

    def process_options(self):
        super(CheckPrestoQueries, self).process_options()
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
        failed_queries = [query_item for query_item in last_n_matching_queries if query_item['state'] == 'FAILED']
        if log.isEnabledFor(logging.INFO):
            for query_item in failed_queries:
                log.info('FAILED query found: %s', query_item['query'])
        num_failed_queries = len(failed_queries)
        self.msg = 'Presto SQL - {0} failed queries'.format(num_failed_queries)
        self.check_thresholds(num_failed_queries)
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
        self.msg += ' | num_failed_queries={0}{1} num_matching_queries={2}:{3}'\
                    .format(num_failed_queries, self.get_perf_thresholds(), num_matching_queries, self.min_queries)


if __name__ == '__main__':
    CheckPrestoQueries().main()
