#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-10-12 22:42:37 +0100 (Wed, 12 Oct 2016)
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

Nagios Plugin to check a specific HBase table's cell value via the Thrift API

Checks:

1. checks HBase table is enabled
2. reads latest HBase cell value for the given table, row key and column family:qualifier
3. checks cell's returned value against expected regex (optional)
4. checks cell's returned value against warning/critical range thresholds (optional)
   raises warning/critical if the value is outside thresholds or not a floating point number
5. outputs the conect and query times to a given precision for reporting and graphing
6. optionally outputs the cell's value for graphing purposes

Tested on Apache HBase 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import re
import sys
import socket
import time
import traceback
try:
    # pylint: disable=wrong-import-position
    import happybase  # pylint: disable=unused-import
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
    from harisekhon.utils import log, qquit, ERRORS, isFloat, isList, support_msg_api
    from harisekhon.utils import validate_host, validate_port, validate_regex, validate_units, validate_int
    from harisekhon.hbase.utils import validate_hbase_table, validate_hbase_rowkey, validate_hbase_column_qualifier
    from harisekhon import NagiosPlugin
except ImportError as _:
    print('harisekhon module import error - did you try copying this program out without the adjacent pylib?\n\n'
          + traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.7'


class CheckHBaseCell(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseCell, self).__init__()
        # Python 3.x
        # super().__init__()
        self.conn = None
        self.host = None
        self.port = None
        self.table = None
        self.row = None
        self.column = None
        self.value = None
        self.regex = None
        self.precision = None
        self.timings = {}
        self.graph = False
        self.units = None
        self.list_tables = False
        self.msg = 'msg not defined'
        self.ok()

    def add_options(self):
        self.add_hostoption(name='HBase Thrift', default_host='localhost', default_port=9090)
        self.add_opt('-T', '--table', help='Table to query')
        self.add_opt('-R', '--row', help='Row to query')
        self.add_opt('-C', '--column', help='Column family:qualifier to query')
        self.add_opt('-e', '--expected', help='Expected regex for the cell\'s value. Optional')
        self.add_thresholds()
        self.add_opt('-p', '--precision', default=2, metavar='int',
                     help='Precision for query timing in decimal places (default: 2)')
        self.add_opt('-g', '--graph', action='store_true', help="Graph the cell's value. Optional, use only if a " +
                     "floating point number is normally returned for it's values, otherwise will print NaN " +
                     "(Not a Number). The reason this is not determined automatically is because keys that change " +
                     "between floats and non-floats will result in variable numbers of perfdata tokens which will " +
                     "break PNP4Nagios")
        self.add_opt('-u', '--units', help="Units to use if graphing cell's value. Optional")
        self.add_opt('-l', '--list', action='store_true', help='List tables and exit')

    def process_options(self):
        self.no_args()
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        self.row = self.get_opt('row')
        self.column = self.get_opt('column')
        self.regex = self.get_opt('expected')
        self.precision = self.get_opt('precision')
        self.graph = self.get_opt('graph')
        self.units = self.get_opt('units')
        validate_host(self.host)
        validate_port(self.port)
        self.list_tables = self.get_opt('list')
        if not self.list_tables:
            self.table = self.get_opt('table')
            validate_hbase_table(self.table, 'hbase')
            validate_hbase_rowkey(self.row)
            validate_hbase_column_qualifier(self.column)
        if self.regex is not None:
            validate_regex('expected value', self.regex)
        if self.units is not None:
            validate_units(self.units)
        self.validate_thresholds(optional=True, positive=False)
        validate_int(self.precision, 'precision', 0, 10)

    def run(self):
        initial_start = time.time()
        try:
            connect_time = self.connect()
            if self.list_tables:
                tables = self.get_tables()
                print('HBase Tables:\n\n' + '\n'.join(tables))
                sys.exit(ERRORS['UNKNOWN'])
            table_conn = self.get_table_conn()
            self.check_read(table_conn, self.row, self.column)
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

    def connect(self):
        log.info('connecting to HBase Thrift Server at %s:%s', self.host, self.port)
        start = time.time()
        # cast port to int to avoid low level socket module TypeError for ports > 32000
        self.conn = happybase.Connection(host=self.host, port=int(self.port), timeout=10 * 1000)  # ms
        connect_time = (time.time() - start) * 1000
        log.info('connected in %s ms', connect_time)
        return connect_time

    def get_tables(self):
        try:
            tables = self.conn.tables()
            if not isList(tables):
                qquit('UNKNOWN', 'table list returned is not a list! ' + support_msg_api())
            return tables
        except (socket.error, socket.timeout, ThriftException, HBaseIOError) as _:
            qquit('CRITICAL', 'error while trying to get table list: {0}'.format(_))

    def get_table_conn(self):
        log.info('checking table \'%s\'', self.table)
        if not self.conn.is_table_enabled(self.table):
            qquit('CRITICAL', "table '{0}' is not enabled!".format(self.table))
        table_conn = self.conn.table(self.table)
        return table_conn

    def check_read(self, table_conn, row, column, expected=None):
        log.info("getting cell for row '%s' column '%s'", row, column)
        cells = []
        query_time = None
        start = time.time()
        cells = table_conn.cells(row, column, versions=1)
        query_time = (time.time() - start) * 1000
        log.info('query read in %s ms', query_time)

        cell_info = "HBase table '{0}' row '{1}' column '{2}'".format(self.table, row, column)

        log.debug('cells returned: %s', cells)
        if not isList(cells):
            qquit('UNKNOWN', 'non-list returned for cells. ' + support_msg_api())

        if len(cells) < 1:
            qquit('CRITICAL', "no cell value found in {0}, does row / column family combination exist?".
                  format(cell_info))
        elif len(cells) > 1:
            qquit('UNKNOWN', "more than one cell returned! " + support_msg_api())

        value = cells[0]
        log.info('value = %s', value)

        if self.regex:
            log.info("checking cell's value '{0}' against expected regex '{1}'".format(value, self.regex))
            if not re.search(self.regex, value):
                qquit('CRITICAL', "cell value '{0}' (expected regex '{1}') for {2}".format(value, self.regex,
                                                                                           cell_info))
        if expected:
            log.info("checking cell's value is exactly expected value '{0}'".format(expected))
            if value != expected:
                qquit('CRITICAL', "cell value '{0}' (expected '{1}') for {2}".format(value, expected, cell_info))
        self.timings[column] = self.timings.get(column, {})
        self.timings[column]['read'] = max(self.timings[column].get('read', 0), query_time)
        self.value = value
        return (value, query_time)

    def output(self, connect_time, total_time):
        precision = self.precision
        cell_info = "HBase table '{0}' row '{1}' column '{2}'".format(self.table, self.row, self.column)
        value = self.value
        self.msg = "cell value = '{0}'".format(value)
        if isFloat(value):
            log.info('value is float, checking thresholds')
            self.check_thresholds(value)
        self.msg += " for {0}".format(cell_info)
        query_time = self.timings[self.column]['read']
        perfdata = ''
        perfdata += ' total_time={0:0.{precision}f}ms'.format(total_time, precision=precision)
        perfdata += ' connect_time={0:0.{precision}f}ms'.format(connect_time, precision=precision)
        perfdata += ' query_time={0:0.{precision}f}ms'.format(query_time, precision=precision)
        # show the timings at the end of the user output as well as in the graphing perfdata section
        self.msg += ',' + perfdata
        self.msg += ' |'
        if self.graph:
            if isFloat(value):
                self.msg += ' value={0}'.format(value)
                if self.units:
                    self.msg += str(self.units)
                self.msg += self.get_perf_thresholds()
            else:
                self.msg += ' value=NaN'
        self.msg += perfdata


if __name__ == '__main__':
    CheckHBaseCell().main()
