#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-10-29 16:16:55 +0100 (Sun, 29 Oct 2017)
#  Old Idea Date: 2014-01-18 14:49:57 +0000 (Sat, 18 Jan 2014)
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

Nagios Plugin to check a given CouchDB server's status via its API

Tested on CouchDB 2.1.0 (does not work on 1.6 as there is no corresponding API endpoint)

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
class CheckCouchdbStatus(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckCouchdbStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['CouchDB', 'Couch']
        self.default_port = 5984
        self.path = '/_up'
        self.auth = False
        self.json = True
        self.msg = 'CouchDB status = '

    def parse_json(self, json_data):
        status = json_data['status']
        self.msg += "'{0}'".format(status)
        if status != 'ok':
            self.critical()


if __name__ == '__main__':
    CheckCouchdbStatus().main()
