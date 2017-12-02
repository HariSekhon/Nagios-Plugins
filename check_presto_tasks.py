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

Nagios Plugin to check the current number of Presto tasks on a Presto Coordinator or Worker node via its API

Warning / Critical thresholds apply to the number of current tasks and it also outputs
graph perfdata of the number of tasks and query time to retrieve this information

This isn't efficent at all as it must get the full list of tasks from the node with their detailed information
(which can be quite large) and parse for non-completed states as the Presto API doesn't expose this
summary information anywhere that I can see (please let me know and I'll write an update if this changes),
but this plugin still completes in 500ms including parsing time

Significant task history may cause this plugin to take longer to return, so watch the graph
on query time from the perfdata that is output

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
    #from harisekhon.utils import UnknownError, support_msg_api, isList
    from check_presto_unfinished_queries import CheckPrestoUnfinishedQueries
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckPrestoTasks(CheckPrestoUnfinishedQueries):

    def __init__(self):
        # Python 2.x
        super(CheckPrestoTasks, self).__init__()
        # Python 3.x
        # super().__init__()
        self.path = '/v1/task'
        self.query_type = 'tasks'
        self.msg = 'Presto msg not defined'

    def add_options(self):
        # Skip CheckPrestoUnfinishedQueries and go straight to it's parent as
        # CheckPrestoUnfinishedQueries sets the defaults to 50 and 200 queries, we want much higher defaults
        # shut up pylint this works
        super(CheckPrestoUnfinishedQueries, self).add_options()  # pylint: disable=bad-super-call
        self.add_thresholds(default_warning=10000, default_critical=50000)

    def filter(self, items):
        """Take a list of queries or tasks and return only the non-finished ones"""
        return [task for task in items if not task['complete'] or \
                                          task['taskStatus']['state'] not in self.finished_states]


if __name__ == '__main__':
    CheckPrestoTasks().main()
