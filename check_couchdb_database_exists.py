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
    from harisekhon.utils import UnknownError, ERRORS, validate_chars, isList, support_msg_api
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4'


class CheckCouchDBDatabaseExists(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckCouchDBDatabaseExists, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['CouchDB', 'Couch']
        self.default_port = 5984
        # HEAD /{db} to test for DB existence slightly more efficiently
        # path set in process options now depending on whether we're listing databases
        # or doing a more efficient HEAD call to check a specific database
        #self.path = '/_all_dbs'
        self.path = None
        self.auth = False
        self.json = True
        self.request_method = 'get'
        self.msg = 'CouchDB database '
        self.database = None

    def check_response_code(self, req):
        if req.status_code != 200:
            #raise CriticalError("database '{0}' does not exist'".format(self.database))
            self.critical()
            self.msg += 'does not exist!'

    def add_options(self):
        super(CheckCouchDBDatabaseExists, self).add_options()
        self.add_opt('-d', '--database', help='Database to assert exists')
        self.add_opt('-g', '--get', action='store_true',
                     help='Do full GET request and assert on db name field' + \
                          ' (default is to do a faster HEAD request only for efficiency)')
        self.add_opt('-l', '--list', action='store_true', default=False, help='List databases and exit')

    def process_options(self):
        super(CheckCouchDBDatabaseExists, self).process_options()
        if self.get_opt('list'):
            self.path = '/_all_dbs'
        else:
            self.database = self.get_opt('database')
            # lowercase characters (a-z), digits (0-9), and any of the characters _, $, (, ), +, -, and /
            validate_chars(self.database, 'database', r'a-z0-9_\$\(\)\+\-/')
            self.path = '/{0}'.format(self.database)
            if not self.get_opt('get'):
                self.request_method = 'head'
                self.json = False
            self.request.check_response_code = self.check_response_code
            self.msg += "'{0}' ".format(self.database)

    # called only for faster HEAD /{db} existence test
    def parse(self, req):
        if req.content:
            raise UnknownError('unexpected output received when using HEAD to /{db} endpoint. {msg}'\
                               .format(db=self.database, msg=support_msg_api()))
        if self.is_ok():
            self.msg += 'exists'

    # called only for listing databases now, HEAD non-json used for simple database existence check
    def parse_json(self, json_data):
        if self.get_opt('list'):
            if not isList(json_data):
                raise UnknownError('non-list returned by CouchDB for databases')
            databases = json_data
            print('CouchDB databases:\n')
            if databases:
                for database in databases:
                    print('{0}'.format(database))
            else:
                print('<none>')
            sys.exit(ERRORS['UNKNOWN'])
        # not testing for DB existance from list of databases any more
#            if self.database in databases:
#                self.ok()
#                self.msg += 'exists'
#            else:
#                self.critical()
#                self.msg += 'does not exist!'
        # now using direct /{db} call instead for specific database
        # exception handling wrapped further up in class hierarchy
        if self.is_ok():
            if json_data['db_name'] != self.database:
                raise UnknownError('db_name {} != {}'.format(json_data['db_name'], self.database))
            self.msg += 'exists'


if __name__ == '__main__':
    CheckCouchDBDatabaseExists().main()
