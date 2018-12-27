#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-06-25 18:16:27 +0100 (Mon, 25 Jun 2018)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#  to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check a Consul service's leader election for a specific leader key in the KV store using API v1

Optional regex check applies to the elected leader to ensure one of the nodes we expect is actually what is elected as
the leader for the service

Tested on Consul 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import json
import os
import re
import sys
import time
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import isStr, isList, support_msg_api, validate_chars, validate_regex, log
    from harisekhon.utils import CriticalError, UnknownError
    from harisekhon.nagiosplugin import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckConsulServiceLeaderElected(RestNagiosPlugin):

    def __init__(self):
        super(CheckConsulServiceLeaderElected, self).__init__()
        self.name = 'Consul'
        self.default_port = 8500
        self.path = '/v1/kv/'
        self.key = None
        self.auth = False
        self.regex = None
        self.msg = 'Consul message not defined yet'

    # closure factory
    @staticmethod
    def check_response_code(msg):
        def tmp(req):
            if req.status_code != 200:
                err = ''
                if req.content and isStr(req.content) and len(req.content.split('\n')) < 2:
                    err += ': ' + req.content
                raise CriticalError("{0}: '{1}' {2}{3}".format(msg, req.status_code, req.reason, err))
        return tmp

    def add_options(self):
        super(CheckConsulServiceLeaderElected, self).add_options()
        self.add_opt('-k', '--key', help='Key to query for elected leader')
        self.add_opt('-r', '--regex',
                     help="Regex to compare the service's elected leader's hostname value against" + \
                          "(optional - this will incur an extra query against the session info)")

    def process_options(self):
        super(CheckConsulServiceLeaderElected, self).process_options()
        self.key = self.get_opt('key')
        self.regex = self.get_opt('regex')
        if not self.key:
            self.usage('--key not defined')
        self.key = self.key.lstrip('/')
        validate_chars(self.key, 'key', r'\w\/-')
        if self.regex:
            validate_regex(self.regex, 'key')
        self.path += '{}'.format(self.key)

    def parse_consul_json(self, name, content):
        json_data = None
        try:
            json_data = json.loads(content)
        except ValueError:
            raise UnknownError("non-json {} data returned by consul at {}:{}: '{}'. {}"\
                               .format(name, self.host, self.port, content, support_msg_api()))
        if not json_data:
            raise UnknownError("blank {} contents returned by consul at {}:{}! '{}'. {}"\
                               .format(name, self.host, self.port, content, support_msg_api()))
        if not isList(json_data):
            raise UnknownError('non-list {} returned by consul at {}:{} for session data. {}'\
                               .format(name, self.host, self.port, support_msg_api()))
        return json_data

    def extract_session(self, req):
        json_data = self.parse_consul_json('key', req.content)
        for item in json_data:
            if 'Session' in item:
                return item['Session']
        return None

    def validate_session(self, req, session):
        json_data = self.parse_consul_json('session', req.content)
        if len(json_data) > 1:
            raise UnknownError("more than 1 session returned for session '{}'!".format(session))
        session_data = json_data[0]
        if 'ID' not in session_data:
            raise UnknownError('no session ID found in session data!')
        if session_data['ID'] != session:
            raise UnknownError("session ID '{}'returned does not match requested session '{}' !!"\
                               .format(session_data['ID'], session))
        if 'Node' not in session_data:
            raise UnknownError('Node field not found in session data! {}'.format(support_msg_api()))
        leader_host = session_data['Node']
        self.msg += ", leader='{}'".format(leader_host)
        if not re.match(self.regex, leader_host):
            self.critical()
            self.msg += " (doesn't match expected regex '{}')".format(self.regex)

    def run(self):
        self.request.check_response_code = \
            self.check_response_code("failed to retrieve Consul key '{0}'".format(self.key))
        start = time.time()
        req = self.query()
        session = self.extract_session(req)
        if not session:
            raise CriticalError('no leader found for service associated with key \'{}\' (no session)!'.format(self.key))
        log.info("session = '%s'", session)
        self.msg = 'Consul service leader found'
        #if self.verbose:
        #    self.msg += " for service at key '{}'".format(self.key)
        if self.regex:
            self.path = '/v1/session/info/{}'.format(session)
            req = self.query()
            self.validate_session(req, session)
        query_time = time.time() - start
        self.msg += ' | query_time={}'.format(query_time)


if __name__ == '__main__':
    CheckConsulServiceLeaderElected().main()
