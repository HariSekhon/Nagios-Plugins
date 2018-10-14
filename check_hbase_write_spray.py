#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-10-13 16:39:15 +0100 (Thu, 13 Oct 2016)
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

Nagios Plugin to check HBase is working by writing to every region of a given table

Checks:

1. table exists
2. table is enabled
3. table is writable - writes one unique qualifier value to each column family detected for every region in the table
4. checks connect & max write / read / delete times in milliseconds against thresholds
5. outputs perfdata of connect & max write / read / delete times

Raises Critical if the table is not enabled or does not exist or if any write / read / delete fails

Tested on Apache HBase 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import logging
import os
import sys
import traceback
#from multiprocessing.pool import ThreadPool
# prefer this to the blocking semantics of Queue.get() in this case
# see pytools/find_active_server.py for usage of Queue.get()
#from collections import deque
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, plural\
                                 #, validate_int #, support_msg_api
    from check_hbase_write import CheckHBaseWrite
except ImportError as _:
    print('harisekhon module import error - did you try copying this program out without the adjacent pylib?\n\n'
          + traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckHBaseWriteSpray(CheckHBaseWrite):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseWriteSpray, self).__init__()
        # Python 3.x
        # super().__init__()
        self.num_regions = None
        self.num_column_families = None
        self.msg = 'msg not defined'
        self.num_threads = None
        self.ok()

    def add_options(self):
        super(CheckHBaseWriteSpray, self).add_options()
        #self.add_opt('-n', '--num-threads', default=10i0, type='int',
        #             help='Number or parallel threads to speed up processing (default: 100)')

    def process_options(self):
        super(CheckHBaseWriteSpray, self).process_options()
        #self.num_threads = self.get_opt('num_threads')
        #validate_int(self.num_threads, 'num threads', 1, 100)

    def check_table(self):
        log.info('checking table \'%s\'', self.table)
        if not self.conn.is_table_enabled(self.table):
            qquit('CRITICAL', "table '{0}' is disabled!".format(self.table))
        table_conn = self.conn.table(self.table)
        families = table_conn.families()
        self.num_column_families = len(families)
        log.info('found %s column families: %s', self.num_column_families, families)
        regions = table_conn.regions()
        self.num_regions = len(regions)
        log.info('found %s regions', self.num_regions)
        if log.isEnabledFor(logging.DEBUG):
            #log.debug('regions list:\n%s', '\n'.join([_['name'] for _ in regions]))
            log.debug('regions list: \n%s', '\n'.join([str(_) for _ in regions]))
        for column_family in sorted(families):
            column = '{0}:{1}'.format(column_family, self.column_qualifier)
            for region in regions:
                self.check_region(table_conn, column, region)
            # Parallelizing this check doesn't seem to save much time, must be losing too much time in code compared to
            # the speed of HBase
            # TODO: variable safe locking in check_hbase_write.py
#            if self.num_threads == 1:
#                for region in regions:
#                    self.check_region(table_conn, column, region)
#            else:
#                # parallelize at the region level
#                log.info('creating thread pool')
#                pool = ThreadPool(processes=self.num_threads)
#                log.info('creating queue')
#                queue = deque()
#                for region in regions:
#                    #log.info('scheduling test of region: %s', region)
#                    pool.apply_async(queue.append((self.check_region(table_conn, column, region))))
#                log.info('waiting for region tests to complete')
#                try:
#                    while True:
#                        queue.popleft()
#                except IndexError:
#                    log.info('all threads finished')

    def check_region(self, table_conn, column, region):
        row = region['start_key'] + self.row
        self.check_write(table_conn, row, column)
        self.check_read(table_conn, row, column, self.value)
        self.check_delete(table_conn, row, column)

    def output(self, connect_time, total_time):
        self.msg = "HBase write spray to {0} column {1} x {2} region{3}".format(self.num_column_families,
                                                                                'families' if \
                                                                                plural(self.num_column_families) \
                                                                                else 'family',
                                                                                self.num_regions,
                                                                                plural(self.num_regions))
        precision = self.precision
        self.msg += " total_time={0:0.{precision}f}ms".format(total_time, precision=precision)
        self.msg += " connect_time={connect_time:0.{precision}f}ms".format(connect_time=connect_time,
                                                                           precision=precision)
        perfdata = " | total_time={total_time:0.{precision}f}ms connect_time={connect_time:0.{precision}f}ms"\
                   .format(total_time=total_time, connect_time=connect_time, precision=precision)
        self.msg += ", max timings: column family "
        for cf_qf in self.timings:
            column = cf_qf.split(':', 2)[0]
            self.msg += "'{0}'".format(column)
            for action in ['write', 'read', 'delete']:
                query_time = self.timings[cf_qf][action]
                self.msg += " {0}_time={1:0.{precision}f}ms".format(action,
                                                                    query_time,
                                                                    precision=precision)
                self.check_thresholds(self.timings[cf_qf][action])
                perfdata += " '{0}_max_{1}_time'={2:0.{precision}f}ms".format(column,
                                                                              action,
                                                                              query_time,
                                                                              precision=precision)
                perfdata += self.get_perf_thresholds()
            self.msg += ', '
        self.msg = self.msg.rstrip(', ')
        self.msg += perfdata


if __name__ == '__main__':
    CheckHBaseWriteSpray().main()
