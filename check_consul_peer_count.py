#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-16 00:46:07 +0000 (Sat, 16 Jan 2016)
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

Nagios Plugin to check the number of peers in a Consul cluster

Tested on Consul 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import json
import os
import sys
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import isList, isStr, support_msg_api, log, uniq_list
    from harisekhon.utils import CriticalError, UnknownError, validate_host, validate_port
    from harisekhon.nagiosplugin import NagiosPlugin
    from harisekhon import RequestHandler
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.7.0'


class CheckConsulPeerCount(NagiosPlugin):

    def __init__(self):
        super(CheckConsulPeerCount, self).__init__()
        self.name = 'Consul'
        self.default_port = 8500
        self.host = None
        self.port = None
        self.request_handler = RequestHandler()
        self.msg = 'NO MESSAGE DEFINED'

    def add_options(self):
        self.add_hostoption(name=self.name, default_host='localhost', default_port=self.default_port)
        self.add_thresholds(default_warning=1, default_critical=1)

    @staticmethod
    def get_peers(content):
        json_data = None
        try:
            json_data = json.loads(content)
        except ValueError:
            raise UnknownError("non-json data returned by consul: '%s'. %s" % (content, support_msg_api()))
        if not json_data:
            raise CriticalError('no peers found, recently started?')
        #if not json_data:
        #    raise UnknownError("blank list returned by consul! '%s'. %s" % (content, support_msg_api()))
        if not isList(json_data):
            raise UnknownError("non-list returned by consul: '%s'. %s" % (content, support_msg_api()))
        for peer in json_data:
            log.debug('peer: {0}'.format(peer))
        peers = uniq_list(json_data)
        return peers

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

    def run(self):
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        validate_host(self.host)
        validate_port(self.port)
        self.validate_thresholds(optional=True, simple='lower')
        url = 'http://%(host)s:%(port)s/v1/status/peers' % self.__dict__
        req = self.request_handler.get(url)
        self.request_handler.check_response_code = \
            self.check_response_code('failed to retrieve Consul peers')
        peers = self.get_peers(req.content)
        peer_count = len(peers)
        self.ok()
        self.msg = 'Consul peer count = {0}'.format(peer_count)
        self.check_thresholds(peer_count)
        self.msg += ' | consul_peer_count={0}'.format(peer_count)
        #self.msg += self.get_perf_thresholds(boundary='lower')
        self.msg += self.get_perf_thresholds(boundary='lower')


if __name__ == '__main__':
    CheckConsulPeerCount().main()
