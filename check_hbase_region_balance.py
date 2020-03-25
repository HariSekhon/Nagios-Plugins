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

Nagios Plugin to check the balance of HBase regions across Region Servers via the HMaster UI

See also check_hbase_table_region_balance.py which uses the HBase Thrift API and can check
region balance for a given table to detect table hotspotting, or region balance for global region
counts like this program.

Tested on Hortonworks HDP 2.3 (HBase 1.1.2) and Apache HBase 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
import os
import re
import sys
import traceback
try:
    from bs4 import BeautifulSoup
    import requests
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, support_msg
    from harisekhon.utils import validate_host, validate_port
    from harisekhon.utils import isInt
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.0'


class CheckHBaseRegionBalance(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseRegionBalance, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'msg not defined'
        self.server_min_regions = ('uninitialized_host', None)
        self.server_max_regions = ('uninitialized_host', None)
        self.status = 'OK'
        self.total_regex = re.compile(r'^Total:\d+')

    def add_options(self):
        self.add_hostoption(name='HBase Master', default_host='localhost', default_port=16010)
        self.add_thresholds(default_warning=10, default_critical=20)

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        validate_host(host)
        validate_port(port)
        self.validate_thresholds(integer=False)

        url = 'http://%(host)s:%(port)s/master-status' % locals()
        log.debug('GET %s', url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            qquit('CRITICAL', _)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        if req.status_code != 200:
            qquit('CRITICAL', ("%s %s" % (req.status_code, req.reason)))
        self.parse_output(req.content)
        log.info('server with min regions = %s regions on %s', self.server_min_regions[1], self.server_min_regions[0])
        log.info('server with max regions = %s regions on %s', self.server_max_regions[1], self.server_max_regions[0])
        imbalance = self.calculate_imbalance()
        self.msg = '{0}% region imbalance'.format(imbalance)
        self.check_thresholds(imbalance)
        self.msg += ' between HBase RegionServers hosting the most vs least number of regions'
        self.msg += ' (min = {0}, max = {1})'.format(self.server_min_regions[1], self.server_max_regions[1])
        self.msg += " | '% region imbalance'={0}%".format(imbalance)
        self.msg += self.get_perf_thresholds()
        self.msg += ' min_regions={0} max_regions={1}'.format(self.server_min_regions[1], self.server_max_regions[1])

    def calculate_imbalance(self):
        max_imbalance = (self.server_max_regions[1] - self.server_min_regions[1]) \
                        / max(self.server_max_regions[1], 1) * 100
        return '{0:.2f}'.format(max_imbalance)

    def parse_output(self, content):
        soup = BeautifulSoup(content, 'html.parser')
        if log.isEnabledFor(logging.DEBUG):
            log.debug("BeautifulSoup prettified:\n{0}\n{1}".format(soup.prettify(), '='*80))
        # shorter to just catch NoneType attribute error when tag not found and returns None
        try:
            basestats = soup.find('div', {'id': 'tab_baseStats'})
            table = basestats.find('table')
            #for table in basestats:
            rows = table.findAll('tr')
            headers = rows[0].findAll('th')
            header_server = headers[0].text
            # HBase 1.1 in HDP 2.3: ServerName | Start time | Requests Per Second | Num. Regions
            # HBase 1.2 (Apache):   ServerName | Start time | Version | Requests per Second | Num. Regions
            # HBase 1.4 (Apache):   ServerName | Start time | Last Contact | Version | Requests Per Second | Num. Regions
            num_regions_index = len(headers) - 1
            header_num_regions = headers[num_regions_index].text
            if header_server != 'ServerName':
                qquit('UNKNOWN', "Table headers in Master UI have changed" +
                      " (got {0}, expected 'ServerName'). ".format(header_server) + support_msg())
            if header_num_regions != 'Num. Regions':
                qquit('UNKNOWN', "Table headers in Master UI have changed" +
                      " (got {0}, expected 'Num. Regions'). ".format(header_num_regions) + support_msg())
            log.debug('%-50s\tnum_regions', 'server')
            for row in rows[1:]:
                # this can be something like:
                # 21689588ba40,16201,1473775984259
                # so don't apply isHost() validation because it'll fail FQDN / IP address checks
                cols = row.findAll('td')
                server = cols[0].text
                if self.total_regex.match(server):
                    continue
                num_regions = cols[num_regions_index].text
                if not isInt(num_regions):
                    qquit('UNKNOWN', "parsing error - got '{0}' for num regions".format(num_regions) +
                          " for server '{}', was expecting integer.".format(server) +
                          " UI format must have changed" + support_msg())
                num_regions = int(num_regions)
                log.debug('%-50s\t%s', server, num_regions)
                if self.server_min_regions[1] is None or num_regions < self.server_min_regions[1]:
                    self.server_min_regions = (server, num_regions)
                if self.server_max_regions[1] is None or num_regions > self.server_max_regions[1]:
                    self.server_max_regions = (server, num_regions)
        except (AttributeError, TypeError, IndexError):
            qquit('UNKNOWN', 'failed to find parse output')


if __name__ == '__main__':
    CheckHBaseRegionBalance().main()
