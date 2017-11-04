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

Nagios Plugin to check if a compaction is running on a CouchDB database via its API

Perfdata as 0 or 1 for compaction running so you can track historically in graphs when compactions run

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
    from check_couchdb_database_stats import CheckCouchDBDatabaseStats
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckCouchDBDatabaseCompaction(CheckCouchDBDatabaseStats):

    def __init__(self):
        # Python 2.x
        super(CheckCouchDBDatabaseCompaction, self).__init__()
        # Python 3.x
        # super().__init__()

    def check_couchdb_stats(self, json_data):
        compact_running = json_data['compact_running']
        self.msg += "'{0}' compaction running = {1}".format(self.database, compact_running)
        if compact_running:
            self.warning()
        self.msg += ' | compact_running={0}'.format(int(compact_running))


if __name__ == '__main__':
    CheckCouchDBDatabaseCompaction().main()
