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

Nagios Plugin to check a given HBase table's regions are assigned

Checks:

1. table exists
2. all regions are assigned to RegionServers
3. table has minimum number of regions for the table vs thresholds

Raises Critical if the table is not enabled or does not exist.
Raises Warning if not all regions are assigned to RegionServers.

This will not test if the table is actually enabled, for that you must use
the adjacent programs check_hbase_table.py or the check_hbase_table_enabled.py

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
    from harisekhon.utils import log, qquit, ERRORS, jsonpp, isList, support_msg_api, plural
    from harisekhon.utils import validate_host, validate_port, validate_database_tablename
    from harisekhon import NagiosPlugin
except ImportError as _:
    print('harisekhon module import error - did you try copying this program out without the adjacent pylib?\n\n'
          + traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4'


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
        self.check_table_regions()

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
        except (socket.error, socket.timeout, ThriftException, HBaseIOError) as _:
            qquit('CRITICAL', 'error while trying to get table list: {0}'.format(_))

    def check_table_regions(self):
        log.info('checking regions for table \'%s\'', self.table)
        regions = None
        try:
            table = self.conn.table(self.table)
            regions = table.regions()
        except HBaseIOError as _:
            #if 'org.apache.hadoop.hbase.TableNotFoundException' in _.message:
            if 'TableNotFoundException' in _.message:
                qquit('CRITICAL', 'table \'{0}\' does not exist'.format(self.table))
            else:
                qquit('CRITICAL', _)
        except (socket.error, socket.timeout, ThriftException) as _:
            qquit('CRITICAL', _)

        if log.isEnabledFor(logging.DEBUG):
            log.debug('%s', jsonpp(regions))
        if not regions:
            qquit('CRITICAL', 'failed to get regions for table \'{0}\''.format(self.table))
        if not isList(regions):
            qquit('UNKNOWN', 'region info returned is not a list! ' + support_msg_api())
        num_regions = len(regions)
        log.info('num regions: %s', num_regions)

        self.msg = 'HBase table \'{0}\' has {1} region{2}'.format(self.table, num_regions, plural(num_regions))
        self.check_thresholds(num_regions)

        num_unassigned_regions = 0
        for region in regions:
            try:
                if not region['server_name']:
                    #log.debug('region \'%s\' is not assigned to any server', region['name'])
                    num_unassigned_regions += 1
            except KeyError as _:
                qquit('UNKNOWN', 'failed to find server assigned to region. ' + support_msg_api())
        log.info('num unassigned regions: %s', num_unassigned_regions)
        self.msg += ', {0} unassigned region{1}'.format(num_unassigned_regions, plural(num_unassigned_regions))
        if num_unassigned_regions > 0:
            self.warning()
            self.msg += '!'

        self.msg += ' |'
        self.msg += ' num_regions={0}'.format(num_regions) + self.get_perf_thresholds(boundary='lower')
        self.msg += ' num_unassigned_regions={0};1;0'.format(num_unassigned_regions)
        log.info('finished, closing connection')
        self.conn.close()


if __name__ == '__main__':
    CheckHBaseTable().main()
