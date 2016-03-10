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

Tested on Consul 0.6.3

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import base64
import json
import os
import re
import sys
import traceback
try:
    import requests
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import qquit, log, isFloat, isList, isStr, support_msg_api
    from harisekhon.utils import WarningError, CriticalError, UnknownError
    from harisekhon.utils import validate_host, validate_port, validate_chars, validate_regex
    from harisekhon.nagiosplugin import KeyCheckNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'

class ConsulKeyCheck(KeyCheckNagiosPlugin):

    def __init__(self):
        super(ConsulKeyCheck, self).__init__()
        self.name = 'Consul'
        self.default_port = 8500

    def extract_value(self, content):  # pylint: disable=no-self-use
        json_data = None
        try:
            json_data = json.loads(content)
        except ValueError:
            qquit('UNKNOWN', "non-json data returned by consul: '%s'. %s" % (content, support_msg_api()))
        value = None
        if not isList(json_data):
            qquit('UNKNOWN', "non-list returned by consul: '%s'. %s" % (content, support_msg_api()))
        if not json_data:
            qquit('UNKNOWN', "blank list returned by consul! '%s'. %s" % (content, support_msg_api()))
        if len(json_data) > 1:
            qquit('UNKNOWN', "more than one key returned by consul! response = '%s'. %s" \
                  % (content, support_msg_api()))
        try:
            value = json_data[0]['Value']
        except KeyError:
            qquit('UNKNOWN', "couldn't find field 'Value' in response from consul: '%s'. %s" \
                  % (content, support_msg_api()))
        try:
            value = base64.decodestring(value)
        except TypeError as _:
            qquit('UNKNOWN', "invalid data returned for key '%(key)s' value = '%(value)s', failed to base64 decode" \
                  % locals())
        return value

    def read(self):
        req = None
        # could use ?raw to get the value without base64 but leaving base64 encoding as it's safer
        url = 'http://%(host)s:%(port)s/v1/kv/%(key)s' % self.__dict__
        log.debug('GET %s' % url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            raise CriticalError(_)
        log.debug("response: %s %s" % (req.status_code, req.reason))
        log.debug("content: '%s'" % req.content)
        if req.status_code != 200:
            err = ''
            if req.content and isStr(req.content) and len(req.content.split('\n')) < 2:
                err += ': ' + req.content
            raise CriticalError("failed to retrieve Consul key '{0}': '{1}' {2}{3}".format(
                                                                            self.key, req.status_code, req.reason, err))
        value = self.extract_value(req.content)
        log.info("value = '%(value)s'" % locals())
        return value


if __name__ == '__main__':
    ConsulKeyCheck().main()
