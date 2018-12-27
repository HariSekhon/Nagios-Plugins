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

Nagios Plugin to check Consul has a leader elected (key writes will fail otherwise)

Tested on Consul 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import re
import sys
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import isStr, CriticalError
    from harisekhon.nagiosplugin import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.7.1'


class CheckConsulLeaderElected(RestNagiosPlugin):

    def __init__(self):
        super(CheckConsulLeaderElected, self).__init__()
        self.name = 'Consul'
        self.default_port = 8500
        self.path = '/v1/status/leader'
        self.auth = False
        self.msg = 'Consul Message Not Defined'
        self.fail_msg = 'Consul leader not elected! Key writes may fail'
        self.request.check_response_code = self.check_response_code(self.fail_msg)

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

    def parse(self, req):
        content = req.content
        if re.match(r'^"\d+\.\d+\.\d+\.\d+:\d+"$', content):
            self.msg = 'Consul leader elected: {0}'.format(content)
        else:
            self.critical()
            self.msg = self.fail_msg
            content = content.strip('"')
            if content and len(content.split('\n')) == 1:
                self.msg += ", output received did not match expected regex: '{0}'".format(content)


if __name__ == '__main__':
    CheckConsulLeaderElected().main()
