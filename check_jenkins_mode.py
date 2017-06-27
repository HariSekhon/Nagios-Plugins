#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-06-27 23:14:03 +0200 (Tue, 27 Jun 2017)
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

Nagios Plugin to check the mode of a Jenkins server via the Rest API

The --password switch accepts either a password or an API token

Tested on Jenkins 2.60.1

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
class CheckJenkinsMode(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsMode, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Jenkins'
        self.default_port = 8080
        self.path = '/api/json'
        self.json = True
        self.msg = self.name + ' mode = '

    def parse_json(self, json_data):
        mode = json_data['mode']
        self.msg += '{0}'.format(mode)
        if mode != 'NORMAL':
            self.msg += ' (expected {0})'.format(mode)
            self.critical()


if __name__ == '__main__':
    CheckJenkinsMode().main()
