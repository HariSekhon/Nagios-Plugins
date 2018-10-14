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

Nagios Plugin to check CouchDB database stats via its API

Outputs:

    - doc count
    - doc del count
    - data size
    - if compaction is running (optional, see also adjacent check_couchdb_database_compaction_running.py
                                which will alert if compaction is running on database to ensure
                                it only happens off peak during maintenance windows)

For threshold tests on each of the above, see adjacent plugins instead

Tested on CouchDB 1.6.1 and 2.1.0

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import traceback
import humanize
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
__version__ = '0.4'


class CheckCouchDBDatabaseStats(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckCouchDBDatabaseStats, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['CouchDB', 'Couch']
        self.default_port = 5984
        self.path = None # set to /<database> further down
        self.auth = False
        self.json = True
        self.msg = 'CouchDB database '
        self.database = None
        self.has_thresholds = False

    def add_options(self):
        super(CheckCouchDBDatabaseStats, self).add_options()
        self.add_opt('-d', '--database', default=os.getenv('COUCHDB_DATABASE'),
                     help='CouchDB Database ($COUCHDB_DATABASE)')
        self.add_opt('-l', '--list', action='store_true', default=False, help='List databases and exit')
        if self.has_thresholds:
            self.add_thresholds()

    def process_options(self):
        super(CheckCouchDBDatabaseStats, self).process_options()
        if self.get_opt('list'):
            self.path = '/_all_dbs'
        else:
            self.database = self.get_opt('database')
            # lowercase characters (a-z), digits (0-9), and any of the characters _, $, (, ), +, -, and /
            validate_chars(self.database, 'database', r'a-z0-9_\$\(\)\+\-/')
            self.path = '/{0}'.format(self.database)
        if self.has_thresholds:
            self.validate_thresholds(optional=True)

    def list_databases(self, json_data):
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

    def parse_json(self, json_data):
        self.list_databases(json_data)
        if json_data['db_name'] != self.database:
            raise UnknownError('db_name {} != {}'.format(json_data['db_name'], self.database))
        self.msg += "'{0}' ".format(self.database)
        self.check_couchdb_stats(json_data)

    def check_couchdb_stats(self, json_data):
        doc_count = json_data['doc_count']
        doc_del_count = json_data['doc_del_count']
        data_size = json_data['data_size']
        #compact_running = json_data['compact_running']
        self.msg += "'{0}' doc count = {1}".format(self.database, doc_count)
        self.check_thresholds(doc_count)
        self.msg += ', doc del count = {0}'.format(doc_del_count)
        self.msg += ', data size = {0}'.format(humanize.naturalsize(data_size))
        self.msg += ' | doc_count={0}{1} doc_del_count={2} data_size={3}b'\
                    .format(doc_count, self.get_perf_thresholds(), doc_del_count, data_size)


if __name__ == '__main__':
    CheckCouchDBDatabaseStats().main()
