#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-09-14 11:10:12 +0200 (Wed, 14 Sep 2016)
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

Nagios Plugin to check HBase's longest current region in transition time (useful to detect regions stuck in transition
as well as graph the time this takes via the perfdata)

See also check_hbase_regions_stuck_in_transition.py which just focuses on the number of regions that have been in
transition for more than the defined number of milliseconds which is another angle of monitoring.

Tested on Hortonworks HDP 2.3 (HBase 1.1.2) and Apache HBase 0.90, 0.92, 0.94, 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

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
    import requests
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, isInt, support_msg
    from harisekhon.utils import validate_host, validate_port
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.1'


class CheckHBaseLongestRegionMigration(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseLongestRegionMigration, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'msg not defined'
        self.ok()

    def add_options(self):
        self.add_hostoption(name='HBase Master', default_host='localhost', default_port=16010)
        self.add_thresholds(default_warning=60, default_critical=120)

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        validate_host(host)
        validate_port(port)
        self.validate_thresholds()

        # observed bug in HDP 2.3 (HBase 1.1.2) where the JMX metric from HMaster UI /jmx is displaying 0 for
        # ritOldestAge, despite currently having regions stuck in transition for a large number of ms
        # [ {"name":"Hadoop:service=HBase,name=Master,sub=AssignmentManger", ..., "ritCountOverThreshold" : 0 }
        # https://issues.apache.org/jira/browse/HBASE-16636
        #url = 'http://%(host)s:%(port)s/jmx' % locals()
        # could get info from flat txt debug page but it doesn't contain the summary count
        #url = 'http://%(host)s:%(port)s/dump' % locals()
        url = 'http://%(host)s:%(port)s/master-status' % locals()
        log.debug('GET %s', url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            qquit('CRITICAL', _)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        if req.status_code != 200:
            qquit('CRITICAL', "%s %s" % (req.status_code, req.reason))
        longest_rit_time = self.parse(req.content)
        if longest_rit_time is None:
            self.msg = 'no regions in transition'
        elif not isInt(longest_rit_time):
            qquit('UNKNOWN', 'parse error - got non-integer \'{0}\' for '.format(longest_rit_time) +
                  'longest regions in transition time when parsing HMaster UI')
        else:
            longest_rit_time /= 1000.0
            self.msg = 'HBase region longest current transition = {0:.2f} secs'.format(longest_rit_time)
            self.check_thresholds(longest_rit_time)
            self.msg += ' | longest_region_in_transition={0}'.format(longest_rit_time)
            self.msg += self.get_perf_thresholds()

    # parsing for /jmx
#    def parse(self, content):
#        jsondict = None
#        try:
#            jsondict = json.loads(content)
#        except ValueError:
#            qquit('UNKNOWN', 'failed to parse returned json')
#        try:
#            _ = jsondict['beans']
#            if not isList(_):
#                qquit('UNKNOWN', 'beans is not a list! ' + support_msg_api())
#            for section in _:
#                if section['name'] == 'Hadoop:service=HBase,name=Master,sub=AssignmentManger':
#                    oldest_age = section['ritOldestAge']
#                    if not isInt(oldest_age):
#                        qquit('UNKNOWN', 'non-integer parsed for ritOldestAge' + support_msg_api())
#                    oldest_age = int(oldest_age)
#                    return oldest_age
#        except (KeyError, ValueError) as _:
#            qquit('UNKNOWN', 'failed to parse JMX data' + support_msg_api())

    def parse(self, content):
        # could also collect lines after 'Regions-in-transition' if parsing /dump
        # sample:
        # hbase:meta,,1.1588230740 state=PENDING_OPEN, \
        # ts=Tue Nov 24 08:26:45 UTC 2015 (1098s ago), server=amb2.service.consul,16020,1448353564099
        soup = BeautifulSoup(content, 'html.parser')
        #if log.isEnabledFor(logging.DEBUG):
        #    log.debug("BeautifulSoup prettified:\n%s\n%s", soup.prettify(), '='*80)
        # looks like HMaster UI doesn't print this section if there are no regions in transition, must assume zero
        longest_rit_time = None
        try:
            headings = soup.findAll('h2')
            for heading in headings:
                log.debug("checking heading '%s'", heading)
                if heading.get_text() == "Regions in Transition":
                    log.debug('found Regions in Transition section header')
                    table = heading.find_next('table')
                    log.debug('checking first following table')
                    rows = table.findChildren('tr')
                    header_cols = rows[0].findChildren('th')
                    self.assert_headers(header_cols)
                    longest_rit_time = self.process_rows(rows)
                    return longest_rit_time
        except (AttributeError, TypeError):
            qquit('UNKNOWN', 'failed to parse HBase Master UI status page. %s' % support_msg())

    @staticmethod
    def process_rows(rows):
        longest_rit_time = None
        # will skip header anyway when it doesn't find td (will contain th instead)
        # this will avoid accidentally skipping a row later if the input changes to rows[1:] instead of rows
        #for row in rows[1:]:
        for row in rows:
            print(row)
            cols = row.findChildren('td')
            # Regions in Transition rows only have 2 cols
            # <hex> region rows have Region, State, RIT time (ms)
            num_cols = len(cols)
            if num_cols == 0:
                # header row
                continue
            elif num_cols != 3:
                qquit('UNKNOWN', 'unexpected number of columns ({0}) '.format(num_cols)
                      + 'for regions in transition table. ' + support_msg())
            if 'Regions in Transition' in cols[0].get_text():
                continue
            rit_time = cols[2].get_text().strip()
            if not isInt(rit_time):
                qquit('UNKNOWN', 'parsing failed, got region in transition time of ' +
                      "'{0}', expected integer".format(rit_time))
            rit_time = int(rit_time)
            if rit_time > longest_rit_time:
                longest_rit_time = rit_time
        return longest_rit_time

    @staticmethod
    def assert_headers(header_cols):
        try:
            if not header_cols[0].get_text().strip() == 'Region':
                raise ValueError('Region')
            if not header_cols[1].get_text().strip() == 'State':
                raise ValueError('State')
            if header_cols[2].get_text().strip() == 'RIT time (ms)':
                raise ValueError('RIT time (ms)')
        except ValueError as _:
            qquit('UNKNOWN', 'parsing failed, headers did not match expected - {0}'.format(_))


if __name__ == '__main__':
    CheckHBaseLongestRegionMigration().main()
