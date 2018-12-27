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

Nagios Plugin to check a given key in a Consul key-value store

Optionally may match the contents against a given regex or numeric thresholds if the key contents are numeric

Tested on Consul 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import base64
import json
import os
import sys
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import isList, isStr, support_msg_api
    from harisekhon.utils import CriticalError, UnknownError
    from harisekhon.nagiosplugin import KeyCheckNagiosPlugin
    from harisekhon import RequestHandler
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.7.0'


class CheckConsulKey(KeyCheckNagiosPlugin):

    def __init__(self):
        super(CheckConsulKey, self).__init__()
        self.name = 'Consul'
        self.default_port = 8500
        self.request_handler = RequestHandler()

    def extract_value(self, content):
        json_data = None
        try:
            json_data = json.loads(content)
        except ValueError:
            raise UnknownError("non-json data returned by consul: '%s'. %s" % (content, support_msg_api()))
        value = None
        if not isList(json_data):
            raise UnknownError("non-list returned by consul: '%s'. %s" % (content, support_msg_api()))
        if not json_data:
            raise UnknownError("blank list returned by consul! '%s'. %s" % (content, support_msg_api()))
        if len(json_data) > 1:
            raise UnknownError("more than one key returned by consul! response = '%s'. %s" \
                  % (content, support_msg_api()))
        try:
            value = json_data[0]['Value']
        except KeyError:
            raise UnknownError("couldn't find field 'Value' in response from consul: '%s'. %s"
                               % (content, support_msg_api()))
        try:
            # decodestring might be deprecated but decodebytes isn't available on Python 2.7
            #value = base64.decodebytes(value)
            value = base64.decodestring(value)
        except TypeError:
            raise UnknownError("invalid data returned for key '{0}' value = '{1}', failed to base64 decode"
                               .format(self.key, value))
        return value

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

    def read(self):
        # could use ?raw to get the value without base64 but leaving base64 encoding as it's safer
        url = 'http://%(host)s:%(port)s/v1/kv/%(key)s' % self.__dict__
        self.request_handler.check_response_code = \
            self.check_response_code("failed to retrieve Consul key '{0}'".format(self.key))
        req = self.request_handler.get(url)
        value = self.extract_value(req.content)
        return value


if __name__ == '__main__':
    CheckConsulKey().main()
