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
#  http://www.linkedin.com/in/harisekhon
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
try:
    import requests
except ImportError as _:
    print('ImportError' % _)
    sys.exit(4)
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import qquit, log, isFloat, isList, isStr, support_msg_api
    from harisekhon.utils import validate_host, validate_port, validate_chars, validate_regex
    from harisekhon import NagiosPlugin
except ImportError as _:
    print('module import failed: %s' % _)
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'

class ConsulCheckKey(NagiosPlugin):

    def add_options(self):
        self.add_hostoption('Consul', default_host='localhost', default_port='8500')
        self.add_opt('-k', '--key', help='Key to query from Consul')
        self.add_opt('-r', '--regex', help="Regex to compare the key's value against (optional)")
        self.add_thresholds()

    def extract_value(self, content): # pylint: disable=no-self-use
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

    def run(self):
        self.no_args()
        host = self.options.host
        port = self.options.port
        validate_host(host)
        validate_port(port)
        key = self.options.key
        regex = self.options.regex
        if not key:
            self.usage('--key not defined')
        key = key.lstrip('/')
        validate_chars(key, 'key', r'\w\/-')
        if regex:
            validate_regex(regex, 'key')
        self.validate_thresholds(optional=True)
        req = None
        url = 'http://%(host)s:%(port)s/v1/kv/%(key)s' % locals()
        log.debug('GET %s' % url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            qquit('CRITICAL', _)
        log.debug("response: %s %s" % (req.status_code, req.reason))
        log.debug("content: '%s'" % req.content)
        if req.status_code != 200:
            err = ''
            if req.content and isStr(req.content) and len(req.content.split('\n')) < 2:
                err += ': ' + req.content
            qquit('CRITICAL', "failed to retrieve consul key '%s': '%s' %s%s" % (key, req.status_code, req.reason, err))
        value = self.extract_value(req.content)
        log.info("value = '%(value)s'" % locals())
        self.ok()
        self.msg = "consul key '%s' value = '%s'" % (key, value)
        if regex:
            if not re.search(regex, value):
                self.critical()
                self.msg += " (did not match expected regex '%s')" % regex
            #elif self.get_verbose():
            #    self.msg += " (matched regex '%s')" % regex
        self.check_thresholds(value)
        if isFloat(value):
            self.msg += " | '%s'=%s" % (key, value)


if __name__ == '__main__':
    ConsulCheckKey().main()
