#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-09-16 14:28:25 +0200 (Fri, 16 Sep 2016)
#  originally started in Perl Date: 2013-11-04 18:22:49 +0000 (Mon, 04 Nov 2013)
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

Nagios Plugin to check the output of HBase hbck and raise an alert if there are any inconsistencies

In order to constrain the runtime of this plugin you must run the HBase HBCK separately and have this plugin check the
output file results. Recommend you do not use any extra switches as it'll enlarge the output and slow down the plugin
by forcing it to parse all the extra noise. As the 'hbase' user run this periodically (via cron):

hbase hbck &> /tmp/hbase-hbck.log.tmp && tail -n30 /tmp/hbase-hbck.log.tmp > /tmp/hbase-hbck.log

Then have the plugin check the results separately (the tail stops the log getting too big and slowing the plugin down
if there are lots of inconsistencies which will end up enlarging the output - it gives us just the bit we need, which
is the summary at the end):

./check_hadoop_fsck.pl -f /tmp/hbase-hbck.log

Tested on Hortonworks HDP 2.3 (HBase 1.1.2) and Apache HBase 1.0.3, 1.1.6, 1.2.1, 1.2.2

See similar check_hadoop_hdfs_fsck.pl for HDFS

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

#import logging
import os
import re
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, isInt, support_msg
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckHBaseHbck(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseHbck, self).__init__()
        # Python 3.x
        # super().__init__()
        self.unknown()
        self.msg = 'msg not defined'
        self.re_status = re.compile(r'^Status:\s*(.+?)\s*$')
        self.re_inconsistencies = re.compile(r'^\s*(\d+)\s+inconsistencies\s+detected\.?\s*$')

    def add_options(self):
        self.add_opt('-f', '--file', dest='file', metavar='<hbck.log>',
                     help='HBase HBCK output file')

    def run(self):
        self.no_args()
        filename = self.get_opt('file')

        if not filename:
            self.usage()

        self.parse(filename)

    def parse(self, filename):
        try:
            num_inconsistencies = None
            hbck_status = None
            log.info('opening file %s', filename)
            with open(filename) as filehandle:
                log.info('parsing file')
                for line in filehandle:
                    match = self.re_status.match(line)
                    if match:
                        hbck_status = match.group(1)
                        log.info('hbck status = %s', hbck_status)
                        continue
                    match = self.re_inconsistencies.match(line)
                    if match:
                        num_inconsistencies = match.group(1)
                        log.info('num inconsistencies = %s', hbck_status)
                        continue
            if hbck_status is None:
                self.parse_error('failed to find hbck status result')
            if num_inconsistencies is None:
                self.parse_error('failed to find number of inconsistencies')
            if not isInt(num_inconsistencies):
                self.parse_error('non-integer detected for num inconsistencies')
            num_inconsistencies = int(num_inconsistencies)
            if hbck_status == 'OK':
                self.ok()
            else:
                self.critical()
            self.msg = 'HBase hbck status = \'{0}\''.format(hbck_status)
            self.msg += ', {0} inconsistencies detected'.format(num_inconsistencies)
            if num_inconsistencies > 0:
                self.critical()
                self.msg += '!'
            self.msg += ' | num_inconsistencies={0};0;0'.format(num_inconsistencies)
        except IOError as _:
            qquit('UNKNOWN', _)

    @staticmethod
    def parse_error(msg):
        qquit('UNKNOWN', 'parse error - ' + msg + '. ' + support_msg())


if __name__ == '__main__':
    CheckHBaseHbck().main()
