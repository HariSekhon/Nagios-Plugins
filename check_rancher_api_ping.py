#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-02-23 18:35:03 +0000 (Fri, 23 Feb 2018)
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

Nagios Plugin to check a Rancher server is up via its API

Tested on Rancher server 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

#import logging
import os
#import re
import sys
#import time
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
class CheckRancherApiPing(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckRancherApiPing, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Rancher'
        self.default_port = 8080
        self.path = '/ping'
        # auth is not needed to this endpoint even when access control is enabled
        self.auth = False
        #self.auth = 'optional'
        self.json = False
        self.msg = 'Rancher msg not defined yet'

#    def add_options(self):
#        super(CheckRancherApiPing, self).add_options()
#
#    def process_options(self):
#        super(CheckRancherApiPing, self).process_options()

    def parse(self, req):
        if req.content.strip() == 'pong':
            self.msg = 'Rancher API ping successful'
        else:
            self.critical()
            self.msg = 'Rancher API ping failed'


if __name__ == '__main__':
    CheckRancherApiPing().main()
