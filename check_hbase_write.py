#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Originally Date of perl version: 2015-02-17 15:52:11 +0000 (Tue, 17 Feb 2015)
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

Nagios Plugin to check HBase is working by writing to a given table

Checks:

1. table exists
2. table is enabled
3. table is writable - writes one unique qualifier value to each column family detected
4. checks connect / write / read / delete times in milliseconds against thresholds
5. outputs perfdata of connect / write / read / delete times

Raises Critical if the table is not enabled or does not exist or if the write fails

Tested on Apache HBase 0.90, 0.92, 0.94, 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import sys
import socket
import time
import traceback
try:
    # pylint: disable=wrong-import-position
    import happybase  # lgtm [py/unused-import]  pylint: disable=unused-import
    # happybase.hbase.ttypes.IOError no longer there in Happybase 1.0
    try:
        # this is only importable after happybase module
        # pylint: disable=import-error
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
    from harisekhon.utils import log, log_option, qquit, ERRORS #, support_msg_api
    from harisekhon.utils import validate_host, validate_port, validate_int, random_alnum, plural
    from harisekhon.hbase.utils import validate_hbase_table
    from check_hbase_cell import CheckHBaseCell
except ImportError as _:
    print('harisekhon module import error - did you try copying this program out without the adjacent pylib?\n\n'
          + traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.5'


class CheckHBaseWrite(CheckHBaseCell):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseWrite, self).__init__()
        # Python 3.x
        # super().__init__()
        self.conn = None
        self.host = None
        self.port = None
        self.table = None
        now = time.time()
        self.row = '{0}#{1}#{2}'.format(random_alnum(10), self._prog, now)
        self.column_qualifier = '{0}#{1}#{2}'.format(self._prog, now, random_alnum(5))
        self.value = '{0}#{1}'.format(now, random_alnum(10))
        self.num_column_families = None
        self.list_tables = False
        self.msg = 'msg not defined'
        self.ok()

    def add_options(self):
        self.add_hostoption(name='HBase Thrift', default_host='localhost', default_port=9090)
        self.add_opt('-T', '--table', help='Table to write to')
        self.add_thresholds(default_warning=20, default_critical=1000)
        self.add_opt('-p', '--precision', default=2, metavar='int',
                     help='Precision for query timing in decimal places (default: 2)')
        self.add_opt('-l', '--list', action='store_true', help='List tables and exit')

    def process_options(self):
        self.no_args()
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        validate_host(self.host)
        validate_port(self.port)
        self.precision = self.get_opt('precision')
        self.list_tables = self.get_opt('list')
        if not self.list_tables:
            self.table = self.get_opt('table')
            validate_hbase_table(self.table, 'hbase')
        self.validate_thresholds(min=1)
        log_option('unique row', self.row)
        log_option('unique column qualifier', self.column)
        log_option('unique generated value', self.value)
        validate_int(self.precision, 'precision', 0, 10)

    def run(self):
        initial_start = time.time()
        try:
            connect_time = self.connect()
            if self.list_tables:
                tables = self.get_tables()
                print('HBase Tables:\n\n' + '\n'.join(tables))
                sys.exit(ERRORS['UNKNOWN'])
            self.check_table()
            log.info('finished, closing connection')
            self.conn.close()
        except HBaseIOError as _:
            #if 'org.apache.hadoop.hbase.TableNotFoundException' in _.message:
            if 'TableNotFoundException' in _.message:
                qquit('CRITICAL', 'table \'{0}\' does not exist'.format(self.table))
            elif 'NoSuchColumnFamilyException' in _.message:
                qquit('CRITICAL', 'column family \'{0}\' does not exist'.format(self.column))
            else:
                qquit('CRITICAL', _)
        except (socket.error, socket.timeout, ThriftException) as _:
            qquit('CRITICAL', _)
        total_time = (time.time() - initial_start) * 1000
        self.output(connect_time, total_time)

    def check_table(self):
        log.info('checking table \'%s\'', self.table)
        if not self.conn.is_table_enabled(self.table):
            qquit('CRITICAL', "table '{0}' is disabled!".format(self.table))
        table_conn = self.conn.table(self.table)
        families = table_conn.families()
        self.num_column_families = len(families)
        log.info('found %s column families: %s', self.num_column_families, families)
        for column_family in sorted(families):
            column = '{0}:{1}'.format(column_family, self.column_qualifier)
            self.check_write(table_conn, self.row, column)
            self.check_read(table_conn, self.row, column, self.value)
            self.check_delete(table_conn, self.row, column)

    def check_write(self, table_conn, row, column):
        log.info("writing cell to row '%s' column '%s'", row, column)
        start_time = time.time()
        table_conn.put(row, {column: self.value})
        query_time = (time.time() - start_time) * 1000
        log.info('query write in %s ms', query_time)
        self.timings[column] = self.timings.get(column, {})
        self.timings[column]['write'] = max(self.timings[column].get('write', 0), query_time)
        return query_time

    def check_delete(self, table_conn, row, column):
        log.info("deleting cell in row '%s' column '%s'", row, column)
        start_time = time.time()
        table_conn.delete(row, [column])
        query_time = (time.time() - start_time) * 1000
        log.info('query delete in %s ms', query_time)
        self.timings[column] = self.timings.get(column, {})
        self.timings[column]['delete'] = max(self.timings[column].get('delete', 0), query_time)
        return query_time

    def output(self, connect_time, total_time):
        self.msg = "HBase write test to {0} column {1}".format(self.num_column_families,
                                                               'families' if plural(self.num_column_families) \
                                                                          else 'family')
        precision = self.precision
        self.msg += " total_time={0:0.{precision}f}ms".format(total_time, precision=precision)
        self.msg += " connect_time={connect_time:0.{precision}f}ms".format(connect_time=connect_time,
                                                                           precision=precision)
        self.msg += ", column family "
        perfdata = " | total_time={total_time:0.{precision}f}ms connect_time={connect_time:0.{precision}f}ms"\
                   .format(total_time=total_time, connect_time=connect_time, precision=precision)
        for cf_qf in self.timings:
            column = cf_qf.split(':', 2)[0]
            self.msg += "'{0}'".format(column)
            for action in ['write', 'read', 'delete']:
                query_time = self.timings[cf_qf][action]
                self.msg += " {0}_time={1:0.{precision}f}ms".format(action,
                                                                    query_time,
                                                                    precision=precision)
                self.check_thresholds(self.timings[cf_qf][action])
                perfdata += " '{0}_{1}_time'={2:0.{precision}f}ms".format(column,
                                                                          action,
                                                                          query_time,
                                                                          precision=precision)
                perfdata += self.get_perf_thresholds()
            self.msg += ', '
        self.msg = self.msg.rstrip(', ')
        self.msg += perfdata


if __name__ == '__main__':
    CheckHBaseWrite().main()
