#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-10-29 16:16:55 +0100 (Sun, 29 Oct 2017)
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

Nagios Plugin to check a given CouchDB database exists via its API

Tested on CouchDB 2.1.0

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
    from harisekhon.utils import UnknownError, ERRORS, validate_chars, isList
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckCouchdbDbExists(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckCouchdbDbExists, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['CouchDB', 'Couch']
        self.default_port = 5984
        self.path = '/_all_dbs'
        self.auth = False
        self.json = True
        self.msg = 'CouchDB database '
        self.database = None

    def add_options(self):
        super(CheckCouchdbDbExists, self).add_options()
        self.add_opt('-d', '--database', help='Database to assert exists')
        self.add_opt('-l', '--list', action='store_true', default=False, help='List databases and exit')

    def process_options(self):
        super(CheckCouchdbDbExists, self).process_options()
        # lowercase characters (a-z), digits (0-9), and any of the characters _, $, (, ), +, -, and /
        self.database = self.get_opt('database')
        validate_chars(self.database, 'database', r'a-z0-9_\$\(\)\+\-/')

    def parse_json(self, json_data):
        if not isList(json_data):
            raise UnknownError('non-list returned by CouchDB for databases')
        databases = json_data
        if self.get_opt('list'):
            print('CouchDB databases:\n')
            for database in databases:
                print('{0}'.format(database))
                sys.exit(ERRORS['UNKNOWN'])
        self.msg += "'{0}' ".format(self.database)
        if self.database in databases:
            self.ok()
            self.msg += 'exists'
        else:
            self.critical()
            self.msg += 'does not exist!'


if __name__ == '__main__':
    CheckCouchdbDbExists().main()
