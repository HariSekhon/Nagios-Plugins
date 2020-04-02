#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2019-02-21 19:05:29 +0000 (Thu, 21 Feb 2019)
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

Nagios Plugin to check Elasticsearch for slow tasks via the API

Thresholds apply to the number of seconds a task has been runnning for

Tested on Elasticsearch 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6

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
    from harisekhon.utils import ERRORS
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckElasticsearchTasksSlow(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckElasticsearchTasksSlow, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Elasticsearch'
        self.default_port = 9200
        self.path = '/_tasks?'
        self.search_type = ''
        self.auth = 'optional'
        self.json = True
        self.msg = 'Elasticsearch msg not defined yet'

    def add_options(self):
        super(CheckElasticsearchTasksSlow, self).add_options()
        self.add_opt('-N', '--node', help='Check tasks on this node only. Matches hostname, IP or node name' + \
                                          '. Careful, getting this wrong will return zero results')
        self.add_opt('-s', '--search-tasks', action='store_true', help='Check only search tasks')
        self.add_opt('-C', '--cluster-tasks', action='store_true', help='Check only cluster tasks')
        self.add_thresholds(default_warning=10, default_critical=100)
        self.add_opt('-l', '--list-tasks', action='store_true', help='List tasks')

    def process_options(self):
        super(CheckElasticsearchTasksSlow, self).process_options()
        cluster_tasks = self.get_opt('cluster_tasks')
        search_tasks = self.get_opt('search_tasks')
        if search_tasks and cluster_tasks:
            self.usage('cannot specify both --search-tasks and --cluster-tasks, they are mutually exclusive')
        if cluster_tasks:
            self.path += 'actions=cluster:*'
            self.search_type = 'cluster '
        if search_tasks:
            self.path += 'actions=search:*'
            self.search_type = 'search '
        if self.get_opt('list_tasks'):
            if self.path[-1] != '?':
                self.path += '&'
            self.path += 'detailed'
        self.validate_thresholds(simple='upper', positive=True, integer=False)

    def parse_json(self, json_data):
        if self.get_opt('list_tasks'):
            self.list_tasks(json_data)
        num_warning = 0
        num_critical = 0
        warning_threshold = self.get_threshold('warning').get_simple()
        critical_threshold = self.get_threshold('critical').get_simple()
        # convert threshold in secs to nanos to compare with running time
        warn_nanos = warning_threshold * 1000 * 1000 * 1000
        crit_nanos = critical_threshold * 1000 * 1000 * 1000
        nodes = json_data['nodes']
        selected_node = self.get_opt('node')
        #found_node = 0
        num_tasks = 0
        for node_id in nodes:
            node = nodes[node_id]
            if selected_node:
                if selected_node not in (node_id, node['host'], node['ip'].split(':')[0], node['name']):
                    continue
                #found_node = 1
            tasks = node['tasks']
            num_tasks += len(tasks)
            for task_id in tasks:
                task = tasks[task_id]
                running_time_in_nanos = task['running_time_in_nanos']
                if running_time_in_nanos > crit_nanos:
                    num_critical += 1
                elif running_time_in_nanos > warn_nanos:
                    num_warning += 1
        #if selected_node and not found_node:
        #    raise UnknownError("node '{}' not found, see --list for available nodes".format(selected_node))
        if num_critical:
            self.critical()
        elif num_warning:
            self.warning()
        for_node_only = " for node '{}'".format(selected_node)
        self.msg = 'Elasticsearch {search_type}tasks = {num_tasks}{for_node_only}'\
                   .format(search_type=self.search_type,
                           num_tasks=num_tasks,
                           for_node_only=for_node_only)
        self.msg += ', warning {num_warning} tasks > {warning_threshold} secs'\
                    .format(num_warning=num_warning,
                            warning_threshold=warning_threshold)
        self.msg += ', critical {num_critical} tasks > {critical_threshold} secs'\
                    .format(num_critical=num_critical,
                            critical_threshold=critical_threshold)
        self.msg += ' | num_tasks={} warning_tasks={} critical_tasks={}'.format(num_tasks, num_warning, num_critical)

    def list_tasks(self, json_data):
        print('Elasticsearch {}tasks:\n'.format(self.search_type))
        print('=' * 80)
        format_string = '{: <10}\t{: <10}\t{: <20}\t{: <30}\t{}'
        print(format_string.format('Node', 'Task ID', 'Running Time in Nanos', 'Action', 'Description'))
        print('=' * 80)
        nodes = json_data['nodes']
        for node_id in nodes:
            node = nodes[node_id]
            tasks = node['tasks']
            for task_id in tasks:
                task = tasks[task_id]
                print(
                    format_string.format(
                        node['host'],
                        task['id'],
                        task['running_time_in_nanos'],
                        task['action'],
                        task['description']
                    )
                )
        sys.exit(ERRORS['UNKNOWN'])


if __name__ == '__main__':
    CheckElasticsearchTasksSlow().main()
