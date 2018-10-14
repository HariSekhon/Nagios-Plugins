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

Nagios Plugin to check the number of HBase regions in transition against thresholds

Tested on Hortonworks HDP 2.3 (HBase 1.1.2) and Apache HBase 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

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
__version__ = '0.2.4'


class CheckHBaseRegionsInTransition(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseRegionsInTransition, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'msg not defined'

    def add_options(self):
        self.add_hostoption(name='HBase Master', default_host='localhost', default_port=16010)
        self.add_thresholds(default_warning=15, default_critical=100)

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        validate_host(host)
        validate_port(port)
        self.validate_thresholds()

        # observed bug in HDP 2.3 (HBase 1.1.2) where the JMX metric from HMaster UI /jmx is displaying 0 for beans
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
        regions_in_transition = self.parse(req.content)
        if regions_in_transition is None:
            qquit('UNKNOWN', 'parse error - failed to find number for regions in transition')
        if not isInt(regions_in_transition):
            qquit('UNKNOWN', 'parse error - got non-integer for regions in transition when parsing HMaster UI')
        if regions_in_transition == 0:
            self.ok()
        else:
            self.critical()
        self.msg = '{0} regions in transition'\
                   .format(regions_in_transition)
        self.check_thresholds(regions_in_transition)
        self.msg += " | regions_in_transition={0}".format(regions_in_transition)
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
#                    regions_in_transition = section['ritCount']
#                    if not isInt(regions_in_transition):
#                        qquit('UNKNOWN', 'non-integer parsed for ritCount. ' + support_msg_api())
#                    regions_in_transition = int(regions_in_transition)
#                    return regions_in_transition
#        except (KeyError, ValueError) as _:
#            qquit('UNKNOWN', 'failed to parse JMX data. ' + support_msg_api())

    def parse(self, content):
        # could also collect lines after 'Regions-in-transition' if parsing /dump
        # sample:
        # hbase:meta,,1.1588230740 state=PENDING_OPEN, \
        # ts=Tue Nov 24 08:26:45 UTC 2015 (1098s ago), server=amb2.service.consul,16020,1448353564099
        soup = BeautifulSoup(content, 'html.parser')
        #if log.isEnabledFor(logging.DEBUG):
        #    log.debug("BeautifulSoup prettified:\n%s\n%s", soup.prettify(), '='*80)
        # looks like HMaster UI doesn't print this section if there are no regions in transition, must assume zero
        regions_in_transition = 0
        try:
            headings = soup.findAll('h2')
            for heading in headings:
                log.debug("checking heading '%s'", heading)
                if heading.get_text() == "Regions in Transition":
                    log.debug('found Regions in Transition section header')
                    table = heading.find_next('table')
                    log.debug('checking first following table')
                    regions_in_transition = self.parse_table(table)
                    if not isInt(regions_in_transition):
                        qquit('UNKNOWN', 'parse error - ' +
                              'got non-integer \'{0}\' for regions in transition when parsing HMaster UI'\
                              .format(regions_in_transition))
            return regions_in_transition
            #qquit('UNKNOWN', 'parse error - failed to find table data for regions in transition')
        except (AttributeError, TypeError):
            qquit('UNKNOWN', 'failed to parse HBase Master UI status page. ' + support_msg())

    @staticmethod
    def parse_table(table):
        for row in table.findChildren('tr'):
            for col in row.findChildren('td'):
                if col.get_text().strip() == 'Regions in Transition':
                    log.debug('found Regions in Transition... getting next td')
                    next_sibling = col.findNext('td')
                    regions_in_transition = next_sibling.get_text().strip()
                    return regions_in_transition
        return None


if __name__ == '__main__':
    CheckHBaseRegionsInTransition().main()
