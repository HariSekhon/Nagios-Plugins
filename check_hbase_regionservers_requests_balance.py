#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-07-13 22:46:34 +0100 (Fri, 13 Jul 2018)
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

Nagios Plugin to check HBase RegionServer requests imbalance via the HMaster UI

Tested on Apache HBase 0.95, 0.96, 0.98, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

#import logging
#import json
import os
import sys
import traceback
try:
    from bs4 import BeautifulSoup
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import isInt, support_msg, UnknownError, plural
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3.0'


class CheckHBaseRegionServerBalance(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseRegionServerBalance, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['HBase Master', 'HBase']
        self.default_port = 16010
        self.path = '/master-status'
        self.auth = False
        self.json = False
        self.msg = 'HBase msg not defined'

    def add_options(self):
        super(CheckHBaseRegionServerBalance, self).add_options()
        self.add_thresholds(default_warning=50)

    def process_options(self):
        super(CheckHBaseRegionServerBalance, self).process_options()
        self.validate_thresholds(percent=True, optional=True)

    def parse(self, req):
        soup = BeautifulSoup(req.content, 'html.parser')
        #if log.isEnabledFor(logging.DEBUG):
        #    log.debug("BeautifulSoup prettified:\n%s\n%s", soup.prettify(), '='*80)
        # this masks underlying exception
        #try:
        tab = soup.find('div', {'id':'tab_baseStats'})
        table = tab.find_next('table')
        rows = table.findChildren('tr')
        if len(rows) < 2:
            raise UnknownError('no regionserver rows found in base stats table! {}'.format(support_msg()))
        # HBase 1.1 in HDP 2.3: ServerName | Start time | Requests Per Second | Num. Regions
        # HBase 1.2 (Apache):   ServerName | Start time | Version | Requests per Second | Num. Regions
        # HBase 1.4 (Apache):   ServerName | Start time | Last Contact | Version | Requests Per Second | Num. Regions
        th_list = rows[0].findChildren('th')
        if len(th_list) < 4:
            raise UnknownError('no table header for base stats table!')
        expected_header = 'Requests Per Second'
        col_index = len(th_list) - 2
        found_header = th_list[col_index].text
        if found_header != expected_header:
            raise UnknownError("wrong table header found for column 4! Expected '{}' but got '{}'. {}"\
                               .format(expected_header, found_header, support_msg()))
        stats = {}
        for row in rows[1:]:
            cols = row.findChildren('td')
            if len(cols) < 4:
                raise UnknownError('4th column in table not found! {}'.format(support_msg()))
            regionserver = cols[0].text.strip().split(',')[0]
            if 'Total:' in regionserver:
                break
            reqs_per_sec = cols[col_index].text.strip()
            if not isInt(reqs_per_sec):
                raise UnknownError("non-integer found in Requests Per Second column for regionserver '{}'. {}"\
                                   .format(regionserver, support_msg()))
            # fix for this is to cast string '1.0' to float and then cast to int
            # ValueError: invalid literal for int() with base 10: '1.0'
            stats[regionserver] = int(float(reqs_per_sec))
        self.process_stats(stats)
        #except (AttributeError, TypeError):
        #    raise UnknownError('failed to parse HBase Master UI status page. {}'.format(support_msg()))

    def process_stats(self, stats):
        lowest_requests = None
        highest_requests = None
        lowest_regionserver = None
        highest_regionserver = None
        for regionserver in stats:
            if lowest_requests is None:
                lowest_requests = stats[regionserver]
                lowest_regionserver = regionserver
            if highest_requests is None:
                highest_requests = stats[regionserver]
                highest_regionserver = regionserver
            if stats[regionserver] > highest_requests:
                highest_requests = stats[regionserver]
                highest_regionserver = regionserver
            if stats[regionserver] < lowest_requests:
                lowest_requests = stats[regionserver]
                lowest_regionserver = regionserver
        # simple algo - let me know if you think can be a better calculation
        imbalance = (highest_requests - lowest_requests) / max(highest_requests, 1) * 100
        num_regionservers = len(stats)
        self.msg = 'HBase RegionServers reqs/sec imbalance = {:.0f}% across {} RegionServer{}'\
                   .format(imbalance, num_regionservers, plural(num_regionservers))
        self.check_thresholds(imbalance)
        if self.verbose or not self.is_ok():
            self.msg += ' [min reqs/sec={} on {} / max reqs/sec={} on {}]'\
                        .format(lowest_requests, lowest_regionserver, highest_requests, highest_regionserver)
        self.msg += ' | reqs_per_sec_balance={:.2f}%{} lowest_requests_per_sec={} highest_requests_per_sec={}'\
                    .format(imbalance, self.get_perf_thresholds(), lowest_requests, highest_requests)


if __name__ == '__main__':
    CheckHBaseRegionServerBalance().main()
