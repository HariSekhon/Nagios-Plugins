#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: Mon Sep 25 10:45:24 CEST 2017
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

Nagios Plugin to check the combined number of running / waiting Presto queries on a Presto Coordinator via its API

This is slighly different to check_presto_queries.py in that instead of selecting specific query types
it includes anything that isn't a finished / failed / cancelled query

Warning / Critical thresholds apply to the number of current / waiting queries and it also outputs
graph perfdata of the number of queries and query time to retrieve this information

This isn't efficent as it must get the full query list and parse for non-completed states as the Presto API
doesn't expose this summary information anywhere that I can see (please let me know and I'll write an update if this
changes), but this plugin still fetches in 120-150ms and completes in 300-700ms in my tests including parsing time

Significant query history may cause this plugin to take longer to return, so watch the graph
on query time from the perfdata that is output

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

import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import UnknownError, support_msg_api, isList
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3.0'


class CheckPrestoUnfinishedQueries(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPrestoUnfinishedQueries, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Presto Coordinator', 'Presto']
        self.default_port = 8080
        self.auth = False
        self.json = True
        self.path = '/v1/query'
        self.query_type = 'queries'
        # queries are usually FINISHED or FAILED
        # tasks can show CANCELLED, CANCELED or closed lowercase (API doc shows CANCELED in both text and sample output)
        # https://github.com/prestodb/presto/blob/master/presto-docs/src/main/sphinx/rest/task.rst
        self.finished_states = ('FINISHED', 'FAILED', 'CANCELLED', 'CANCELED', 'closed')
        self.msg = 'Presto msg not defined'

    def add_options(self):
        super(CheckPrestoUnfinishedQueries, self).add_options()
        self.add_thresholds(default_warning=50, default_critical=200)

    def process_options(self):
        super(CheckPrestoUnfinishedQueries, self).process_options()
        self.validate_thresholds()

    def filter(self, items):
        """Take a list of queries and return only the non-finished ones"""
        return [query for query in items if query['state'] not in self.finished_states]

    def parse_json(self, json_data):
        if not isList(json_data):
            raise UnknownError('non-list returned by Presto for {type}. {msg}'.format(
                type=self.query_type, msg=support_msg_api()))
        current_queries = self.filter(json_data)
        num_queries = len(current_queries)
        self.msg = 'Presto SQL - {0} current {1}'.format(num_queries, self.query_type)
        self.check_thresholds(num_queries)
        # check_presto_num_tasks.py works against workers too
        #self.msg += ' on {0}'.format(self.query_on_node)
        if self.verbose:
            self.msg += ' {0}:{1}'.format(self.host, self.port)
        self.msg += ' | num_current_{type}={num}{thresholds}'.format(
            type=self.query_type,
            num=num_queries,
            thresholds=self.get_perf_thresholds())


if __name__ == '__main__':
    CheckPrestoUnfinishedQueries().main()
