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

Nagios Plugin to check for HBase Regions stuck in transition (this will prevent region rebalancing)

Tested on Hortonworks HDP 2.3 (HBase 1.1.6) and Apache HBase 1.0.3, 1.1.6, 1.2.2

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import json
import os
import sys
import traceback
try:
    import requests
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, support_msg_api, isList, isInt
    from harisekhon.utils import validate_host, validate_port
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckHbaseRegionsStuckInTransition(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHbaseRegionsStuckInTransition, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'msg not defined'
        self.regions_stuck_in_transition = None

    def add_options(self):
        self.add_hostoption(name='HBase Master', default_host='localhost', default_port=16010)

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        validate_host(host)
        validate_port(port)

        # can also see this on the page
        #url = 'http://%(host)s:%(port)s/dump' % locals()
        url = 'http://%(host)s:%(port)s/jmx' % locals()
        log.debug('GET %s', url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            quit('CRITICAL', _)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        if req.status_code != 200:
            qquit('CRITICAL', "%s %s" % (req.status_code, req.reason))
        self.parse(req.content)
        if self.regions_stuck_in_transition == 0:
            self.ok()
        else:
            self.critical()
        self.msg = '{0} regions stuck in transition (ie. transitioning longer than HBase threshold)'\
                   .format(self.regions_stuck_in_transition)
        self.msg += " | regions_stuck_in_transition={0};0;0".format(self.regions_stuck_in_transition)

    def parse(self, content):
        # collect lines after 'Regions-in-transition' if parsing /dump
        # sample:
        # hbase:meta,,1.1588230740 state=PENDING_OPEN, \
        # ts=Tue Nov 24 08:26:45 UTC 2015 (1098s ago), server=amb2.service.consul,16020,1448353564099
        jsondict = None
        try:
            jsondict = json.loads(content)
        except ValueError:
            qquit('UNKNOWN', 'failed to parse returned json')
        try:
            _ = jsondict['beans']
            if not isList(_):
                qquit('UNKNOWN', 'beans is not a list! ' + support_msg_api())
            for section in _:
                if section['name'] == 'Hadoop:service=HBase,name=Master,sub=AssignmentManger':
                    self.regions_stuck_in_transition = section['ritCountOverThreshold']
                    if not isInt(self.regions_stuck_in_transition):
                        qquit('UNKNOWN', 'non-integer parsed for ritCountOverThreshold' + support_msg_api())
                    self.regions_stuck_in_transition = int(self.regions_stuck_in_transition)
                    break
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', 'failed to parse JMX data' + support_msg_api())

if __name__ == '__main__':
    CheckHbaseRegionsStuckInTransition().main()
