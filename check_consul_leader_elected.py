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

Tested on Consul 0.6.3

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
    from harisekhon.nagiosplugin import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.6.1'


# pylint: disable=too-few-public-methods
class CheckConsulLeaderElected(RestNagiosPlugin):

    def __init__(self):
        super(CheckConsulLeaderElected, self).__init__()
        self.name = 'Consul'
        self.default_port = 8500
        self.path = '/v1/status/leader'
        self.auth = False
        self.msg = 'Consul Message Not Defined'

    def parse(self, req):
        content = req.content
        if re.match(r'^"\d+\.\d+\.\d+\.\d+:\d+"$', str(content)):
            self.msg = 'Consul leader elected: {0}'.format(content)
        else:
            self.critical()
            self.msg = 'Consul leader not elected! Key writes may fail'
            if len(content.split('\n')) == 1:
                self.msg += ", output received did not match expected regex: '{0}'".format(content)


if __name__ == '__main__':
    CheckConsulLeaderElected().main()
