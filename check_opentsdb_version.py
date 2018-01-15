#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-01-15 17:59:23 +0000 (Mon, 15 Jan 2018)
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

Nagios Plugin to check the version of OpenTSDB via its Rest API

Tested on OpenTSDB 2.2

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
    #from harisekhon.utils import support_msg_api
    from harisekhon import RestVersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckOpenTSDBVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckOpenTSDBVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'OpenTSDB'
        self.default_port = 4242
        self.path = '/api/version'
        self.json = True
        self.auth = False
        self.json_data = None
        self.ok()

    def parse_json(self, json_data):
        self.json_data = json_data
        version = json_data['version']
        #version = version.split('-')[0]
        #if not self.verbose:
        #    version = '.'.join(version.split('.')[0:3])
        return version


if __name__ == '__main__':
    CheckOpenTSDBVersion().main()
