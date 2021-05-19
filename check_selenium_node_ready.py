#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2021-05-16 09:59:33 +0100 (Sun, 16 May 2021)
#
#  https://github.com/HariSekhon/Nagios-Plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/HariSekhon
#

"""

Nagios Plugin to check a Selenium Node is up with a ready status via its Rest API

Also prints status message from Node software


Tested on Selenium Grid Node 4.0.0

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
    from check_selenium_hub_ready import CheckSeleniumHubReady
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckSeleniumNodeReady(CheckSeleniumHubReady):

    def __init__(self):
        # Python 2.x
        super(CheckSeleniumNodeReady, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Selenium Node'
        self.default_port = 5555
        self.path = '/status'
        self.auth = False
        self.json = True
        self.protocol = 'http'
        self.msg = 'Selenium Node Msg not defined yet'

    def parse_json(self, json_data):
        data = json_data['value']
        ready = data['ready']
        message = data['message']
        message = message.rstrip('.')
        if ready:
            self.ok()
        else:
            self.critical()
        self.msg = 'Selenium Node ready status = {}, message = {}'.format(ready, message)


if __name__ == '__main__':
    CheckSeleniumNodeReady().main()
