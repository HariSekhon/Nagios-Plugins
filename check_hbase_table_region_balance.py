#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-09-12 11:13:31 +0200 (Mon, 12 Sep 2016)
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

Nagios Plugin to check the balance of HBase regions across Region Servers via the HBase Thrift Server API

Checks:

1. if --table is specified checks the balance of regions across RegionServers for a given table
   (to check for table hotspotting)
2. if no --table is specified then checks the balance of total regions across all RegionServers
   to check for general region hotspotting (indicative of failure to rebalance)

See also check_hbase_region_balance.py which parses the HMaster UI instead of using the Thrift API
and checks the balance of total regions across all RegionServers

Tested on Hortonworks HDP 2.3 (HBase 1.1.2) and Apache HBase 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import socket
import sys
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
except ImportError:
    print('Happybase / thrift module import error - did you forget to build this project?\n\n'
          + traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, ERRORS, support_msg_api
    from harisekhon.utils import validate_host, validate_port
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckHBaseTableRegionBalance(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseTableRegionBalance, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'msg not defined'
        self.conn = None
        self.server_region_counts = {}
        self.server_min_regions = (None, 0)
        self.server_max_regions = (None, 0)
        self.status = 'OK'
        self.table = None

    def add_options(self):
        self.add_hostoption(name='HBase Thrift', default_host='localhost', default_port=9090)
        self.add_opt('-T', '--table', help='Table to check')
        self.add_opt('-l', '--list-tables', action='store_true', help='List tables and exit')
        self.add_thresholds(default_warning=10, default_critical=20)

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        self.table = self.get_opt('table')
        validate_host(host)
        validate_port(port)
        self.validate_thresholds(integer=False)

        try:
            log.info('connecting to HBase Thrift Server at %s:%s', host, port)
            # cast port to int to avoid low level socket module TypeError for ports > 32000
            self.conn = happybase.Connection(host=host, port=int(port), timeout=10 * 1000)  # ms
        except (socket.error, socket.timeout, ThriftException, HBaseIOError) as _:
            qquit('CRITICAL', 'error connecting: {0}'.format(_))
        tables = self.conn.tables()
        if len(tables) < 1:
            qquit('CRITICAL', 'no HBase tables found!')
        if self.get_opt('list_tables'):
            print('Tables:\n\n' + '\n'.join(tables))
            sys.exit(ERRORS['UNKNOWN'])
        if self.table:
            if self.table not in tables:
                qquit('CRITICAL', "HBase table '{0}' does not exist!".format(self.table))
            self.process_table(self.table)
        else:
            for table in tables:
                self.process_table(table)
        log.info('finished, closing connection')
        self.conn.close()

        imbalance = self.calculate_imbalance()

        self.msg = '{0}% region imbalance'.format(imbalance)
        self.check_thresholds(imbalance)
        self.msg += ' between HBase RegionServers hosting the most vs least number of regions'
        if self.table:
            self.msg += " for table '{0}'".format(self.table)
        else:
            self.msg += ' across all tables'
        self.msg += ' (min = {0}, max = {1})'.format(self.server_min_regions[1], self.server_max_regions[1])
        self.msg += " | '% region imbalance'={0}%".format(imbalance)
        self.msg += self.get_perf_thresholds()
        self.msg += ' min_regions={0} max_regions={1}'.format(self.server_min_regions[1], self.server_max_regions[1])

    def process_table(self, table):
        try:
            table_handle = self.conn.table(table)
            regions = table_handle.regions()
            if len(regions) < 1:
                qquit('UNKNOWN', "no regions found for table '{0}'".format(table))
            for region in regions:
                log.debug("table '%s' region '%s'", table, region)
                server = region['server_name']
                self.server_region_counts[server] = self.server_region_counts.get(server, 0)
                self.server_region_counts[server] += 1
        except (socket.error, socket.timeout, ThriftException, HBaseIOError) as _:
            qquit('CRITICAL', _)
        except KeyError as _:
            qquit('UNKNOWN', 'failed to process region information. ' + support_msg_api())

    def calculate_imbalance(self):
        for server in self.server_region_counts:
            num_regions = self.server_region_counts[server]
            if self.server_max_regions[0] is None or num_regions > self.server_max_regions[1]:
                self.server_max_regions = (server, num_regions)
            if self.server_min_regions[0] is None or num_regions < self.server_min_regions[1]:
                self.server_min_regions = (server, num_regions)
        log.info('server with min regions = %s regions on %s', self.server_min_regions[1], self.server_min_regions[0])
        log.info('server with max regions = %s regions on %s', self.server_max_regions[1], self.server_max_regions[0])
        imbalance = (self.server_max_regions[1] - self.server_min_regions[1]) \
                         / max(self.server_max_regions[1], 1) * 100
        return imbalance


if __name__ == '__main__':
    CheckHBaseTableRegionBalance().main()
