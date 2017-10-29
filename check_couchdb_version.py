#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-10-29 15:59:02 +0100 (Sun, 29 Oct 2017)
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

Nagios Plugin to check the version of a CouchDB server its API

Tested on CouchDB 1.6.1 and 2.1.0

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
    from harisekhon import RestVersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckCouchDBVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckCouchDBVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['CouchDB', 'Couch']
        self.default_port = 5984
        self.path = '/'
        self.json = True
        self.auth = False
        #self.lax_version = True

    # must override, cannot change to @staticmethod
    def parse_json(self, json_data):  # pylint: disable=no-self-use
        version = json_data['version']
        return version


if __name__ == '__main__':
    CheckCouchDBVersion().main()
