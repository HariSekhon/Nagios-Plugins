#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-03-27 22:34:24 +0000 (Fri, 27 Mar 2020)
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

Nagios Plugin to check the health of a GoCD agent via its API

Tested on GoCD 20.2.0

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
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckGoCDAgentHealth(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckGoCDAgentHealth, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'GoCD Agent'
        self.default_port = 8152
        self.path = '/health/v1/isConnectedToServer'
        # didn't make any difference
        #self.headers = {
        #    'Accept': 'application/vnd.go.cd.v1+json'
        #}
        self.auth = 'optional'
        self.json = False
        self.msg = 'GoCD msg not defined yet'

    def parse(self, req):
        content = req.content
        if content != 'OK!':
            self.critical()
        self.msg = 'GoCD agent health = {}'.format(content)


if __name__ == '__main__':
    CheckGoCDAgentHealth().main()
