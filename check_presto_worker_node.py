#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-10-12 16:55:53 +0200 (Thu, 12 Oct 2017)
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

Nagios Plugin to check for a specific Presto SQL worker node via the Coordinator API

Checks worker node:

    - is found on Coordinator
    - time since last response to Coordinator vs threshold (raises critical)
    - recent requests vs threshold (raises warning)
    - recent failures vs threshold (raises critical)
    - recent failure ratio vs threshold (raises critical)
    - shows uptime of the worker node

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

from datetime import datetime
import os
import re
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import ERRORS, UnknownError, CriticalError, support_msg_api, \
                                 isList, isFloat, validate_float
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3.0'


class CheckPrestoWorker(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPrestoWorker, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Presto Coordinator', 'Presto']
        self.default_port = 8080
        self.auth = False
        self.json = True
        self.path = '/v1/node'
        self.node = None
        self.max_age = None
        self.max_ratio = None
        self.max_failures = None
        self.max_requests = None
        self.list_nodes = None
        self.msg = 'Presto msg not defined'

    def add_options(self):
        super(CheckPrestoWorker, self).add_options()
        self.add_opt('-N', '--node', metavar='node_host:node_port',
                     help='Node to query for, use --list-nodes for what to enter here' + \
                          ', can omit http:// uri prefix and port suffix for convenience')
        self.add_opt('-a', '--max-age', metavar='secs', default=10,
                     help='Max age in secs since worker\'s last response to coordinator (default: 10)')
        self.add_opt('-R', '--max-ratio', metavar='0.0', default=0.0,
                     help='Max recent failure ratio (default: 0.0)')
        self.add_opt('-f', '--max-failures', metavar='0', default=0,
                     help='Max number of recent failures to tolerate on the worker (default: 0)')
        self.add_opt('-r', '--max-requests', metavar='0', default=None,
                     help='Max number of recent requests to tolerate on the worker (default: none, check disabled)')
        self.add_opt('-l', '--list-nodes', action='store_true', help='List worker nodes and exit')

    def process_options(self):
        super(CheckPrestoWorker, self).process_options()
        self.node = self.get_opt('node')
        self.list_nodes = self.get_opt('list_nodes')
        if not self.node and not self.list_nodes:
            self.usage('--node not defined')
        self.max_age = self.get_opt('max_age')
        validate_float(self.max_age, 'max age', 0, 3600)
        self.max_age = int(self.max_age)

        self.max_requests = self.get_opt('max_requests')
        if self.max_requests is not None:
            validate_float(self.max_requests, 'max recent requests', 0, None)
            self.max_requests = float('{0:.2f}'.format(float(self.max_requests)))

        self.max_failures = self.get_opt('max_failures')
        validate_float(self.max_failures, 'max recent failures', 0, None)
        self.max_failures = float('{0:.2f}'.format(float(self.max_failures)))

        self.max_ratio = self.get_opt('max_ratio')
        validate_float(self.max_ratio, 'max recent failure ratio', 0, 1.0)
        self.max_ratio = float('{0:.2f}'.format(float(self.max_ratio)))

    @staticmethod
    def get_nodes(json_data):
        if not isList(json_data):
            raise UnknownError('non-list returned by Presto for nodes. {0}'.format(support_msg_api()))
        return json_data

    @staticmethod
    def get_node_name(node_item):
        return node_item['uri']

    def print_nodes(self, node_list):
        print('Presto SQL Worker Nodes:\n')
        for _ in node_list:
            print(self.get_node_name(_))

    @staticmethod
    def get_recent_failure_ratio(node):
        recent_failure_ratio = node['recentFailureRatio']
        if not isFloat(recent_failure_ratio):
            raise UnknownError('recentFailureRatio is not a float! {0}'.format(support_msg_api()))
        recent_failure_ratio = float('{0:.2f}'.format(recent_failure_ratio))
        if recent_failure_ratio < 0:
            raise UnknownError('recentFailureRatio < 0 ?!!! {0}'.format(support_msg_api()))
        if recent_failure_ratio > 1:
            raise UnknownError('recentFailureRatio > 1 ?!!! {0}'.format(support_msg_api()))
        return recent_failure_ratio

    @staticmethod
    def get_stat(node, stat):
        stat_num = node[stat]
        if not isFloat(stat_num):
            raise UnknownError('{stat} is not a float! {msg}'.format(stat=stat, msg=support_msg_api()))
        stat_num = float('{0:.2f}'.format(stat_num))
        if stat_num < 0:
            raise UnknownError('{stat} < 0 ?!!! {msg}'.format(stat=stat, msg=support_msg_api()))
        return stat_num

    @staticmethod
    def get_response_age(node):
        if not 'lastResponseTime' in node:
            raise UnknownError('lastResponseTime field not found in node data, if node was just started this may ' + \
                               'not be populated until second run. If this error persists then {0}'\
                               .format(support_msg_api()))
        last_response_time = node['lastResponseTime']
        last_response_datetime = datetime.strptime(last_response_time, '%Y-%m-%dT%H:%M:%S.%fZ')
        timedelta = datetime.utcnow() - last_response_datetime
        response_age = timedelta.total_seconds()
        return response_age

    def parse_json(self, json_data):
        node_list = self.get_nodes(json_data)
        if self.list_nodes:
            self.print_nodes(node_list)
            sys.exit(ERRORS['UNKNOWN'])
        node = None
        re_protocol = re.compile(r'^https?://')
        re_port = re.compile(r':\d+$')
        for _ in node_list:
            uri = self.get_node_name(_)
            uri_host_port = re_protocol.sub('', uri)
            uri_host = re_port.sub('', uri_host_port)
            if self.node == uri or \
               self.node == uri_host_port or \
               self.node == uri_host:
                node = _
                break
        if not node:
            raise CriticalError("Presto SQL worker node '{0}' not found on coordinator!".format(self.node))
        response_age = self.get_response_age(node)
        recent_requests = self.get_stat(node, 'recentRequests')
        recent_successes = self.get_stat(node, 'recentSuccesses')
        recent_failures = self.get_stat(node, 'recentFailures')
        recent_failure_ratio = self.get_recent_failure_ratio(node)
        uptime = node['age']
        self.msg = "Presto SQL worker node '{0}' ".format(self.node)
        self.msg += 'last response to coordinator = {0:.2f} secs ago'.format(response_age)
        if response_age > self.max_age:
            self.critical()
            self.msg += ' (> {0})'.format(self.max_age)
        self.msg += ', recent requests = {0:.2f}'.format(recent_requests)
        if self.max_requests is not None and recent_requests > self.max_requests:
            self.warning()
            self.msg += ' (> {0})'.format(self.max_requests)
        self.msg += ', recent successes = {0:.2f}'.format(recent_successes)
        self.msg += ', recent failures = {0:.2f}'.format(recent_failures)
        if recent_failures > self.max_failures:
            self.critical()
            self.msg += ' (> {0})'.format(self.max_failures)
        self.msg += ', recent failure ratio = {0:.2f}'.format(recent_failure_ratio)
        if recent_failure_ratio > self.max_ratio:
            self.critical()
            self.msg += ' (> {0})'.format(self.max_ratio)
        self.msg += ', uptime = {0}'.format(uptime)
        self.msg += ' | '
        self.msg += 'response_age={0}s;{1:.2f} '.format(response_age, self.max_age)
        self.msg += 'recent_requests={0:.2f} '.format(recent_requests)
        self.msg += 'recent_successes={0:.2f}'.format(recent_successes)
        self.msg += 'recent_failures={0:.2f};{1:.2f} '.format(recent_failures, self.max_failures)
        self.msg += 'recent_failure_ratio={0:.2f};{1:.2f} '.format(recent_failure_ratio, self.max_ratio)


if __name__ == '__main__':
    CheckPrestoWorker().main()
