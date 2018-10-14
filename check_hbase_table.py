#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-09-25 09:32:49 +0100 (Sun, 25 Sep 2016)
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

Nagios Plugin to check a given HBase table

Checks:

1. table exists
2. table is enabled
3. table has minimum number of column families vs thresholds

Raises Critical if the table is not enabled or does not exist

Tested on Apache HBase 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import logging
import os
import sys
import socket
import traceback
try:
    # pylint: disable=wrong-import-position
    import happybase  # pylint: disable=unused-import
    # happybase.hbase.ttypes.IOError no longer there in Happybase 1.0
    try:
        # pylint: disable=import-error
        # this is only importable after happybase module
        # this is what the happybase module is doing:
        # pylint still doesn't understand this if I put it ahead of the Hbase_thrift import
        #import thriftpy as _thriftpy
        #import pkg_resources as _pkg_resources
        #_thriftpy.load(
        #    _pkg_resources.resource_filename('happybase', 'Hbase.thrift'),
        #    'Hbase_thrift')
        from Hbase_thrift import IOError as HBaseIOError
    except ImportError:
        # probably Happybase <= 0.9
        # pylint: disable=import-error,no-name-in-module,ungrouped-imports
        from happybase.hbase.ttypes import IOError as HBaseIOError
    from thriftpy.thrift import TException as ThriftException
except ImportError as _:
    print('Happybase / thrift module import error - did you forget to build this project?\n\n'
          + traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, ERRORS, jsonpp, isDict, isList, support_msg_api
    from harisekhon.utils import validate_host, validate_port, validate_database_tablename
    from harisekhon import NagiosPlugin
except ImportError as _:
    print('harisekhon module import error - did you try copying this program out without the adjacent pylib?\n\n'
          + traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.6'


class CheckHBaseTable(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseTable, self).__init__()
        # Python 3.x
        # super().__init__()
        self.conn = None
        self.host = None
        self.port = None
        self.table = None
        self.list_tables = False
        self.msg = 'msg not defined'
        self.ok()

    def add_options(self):
        self.add_hostoption(name='HBase Thrift', default_host='localhost', default_port=9090)
        self.add_opt('-T', '--table', help='Table to check is enabled')
        self.add_opt('-l', '--list', action='store_true', help='List tables and exit')
        self.add_thresholds(default_warning=1, default_critical=1)

    def run(self):
        self.no_args()
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        validate_host(self.host)
        validate_port(self.port)
        self.list_tables = self.get_opt('list')
        if not self.list_tables:
            self.table = self.get_opt('table')
            validate_database_tablename(self.table, 'hbase')
        self.validate_thresholds(simple='lower', min=1)
        self.connect()
        if self.list_tables:
            tables = self.get_tables()
            print('HBase Tables:\n\n' + '\n'.join(tables))
            sys.exit(ERRORS['UNKNOWN'])
        self.check_table()

    def connect(self):
        log.info('connecting to HBase Thrift Server at %s:%s', self.host, self.port)
        try:
            # cast port to int to avoid low level socket module TypeError for ports > 32000
            self.conn = happybase.Connection(host=self.host, port=int(self.port), timeout=10 * 1000)  # ms
        except (socket.error, socket.timeout, ThriftException, HBaseIOError) as _:
            qquit('CRITICAL', 'error connecting: {0}'.format(_))

    def get_tables(self):
        try:
            tables = self.conn.tables()
            if not isList(tables):
                qquit('UNKNOWN', 'table list returned is not a list! ' + support_msg_api())
            return tables
        except (socket.error, socket.timeout, ThriftException, HBaseIOError) as _:
            qquit('CRITICAL', 'error while trying to get table list: {0}'.format(_))

    def check_table(self):
        log.info('checking table \'%s\'', self.table)
        is_enabled = None
        families = None
        try:
            is_enabled = self.conn.is_table_enabled(self.table)
            log.info('enabled: %s', is_enabled)
            table = self.conn.table(self.table)
            families = table.families()
        except HBaseIOError as _:
            #if 'org.apache.hadoop.hbase.TableNotFoundException' in _.message:
            if 'TableNotFoundException' in _.message:
                qquit('CRITICAL', 'table \'{0}\' does not exist'.format(self.table))
            else:
                qquit('CRITICAL', _)
        except (socket.error, socket.timeout, ThriftException) as _:
            qquit('CRITICAL', _)

        if log.isEnabledFor(logging.DEBUG):
            log.debug('column families:\n%s', jsonpp(families))
        if not families:
            qquit('CRITICAL', 'failed to get column families for table \'{0}\''.format(self.table))
        if not isDict(families):
            qquit('UNKNOWN', 'column family info returned was not a dictionary! ' + support_msg_api())
        num_families = len(families)
        log.info('num families: %s', num_families)

        self.msg = 'HBase table \'{0}\' is '.format(self.table)
        if is_enabled:
            self.msg += 'enabled, '
        else:
            self.critical()
            self.msg += 'disabled! '

        self.msg += '{0} column '.format(num_families)
        if num_families == 1:
            self.msg += 'family'
        else:
            self.msg += 'families'
        self.check_thresholds(num_families)

        self.msg += ' | num_column_families={0}'.format(num_families) + self.get_perf_thresholds(boundary='lower')
        log.info('finished, closing connection')
        self.conn.close()


if __name__ == '__main__':
    CheckHBaseTable().main()
