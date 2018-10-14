#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-07-09 19:54:57 +0100 (Mon, 09 Jul 2018)
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

Nagios Plugin to check the HBase Balancer is enabled by scraping the HMaster JSP UI

Raises warning if the HBase Balancer isn't enabled

This has to search the HMaster UI web page for the warning string, so this is brittle
and could miss the balancer not being abled if HBase UI were to change upstream as
this won't be able to detect the change

Would prefer to get this out of the JMX but the info isn't available, see:

https://issues.apache.org/jira/browse/HBASE-20857

See also check_hbase_balancr_enabled2.py for a version which parses the HTML properly
and is more likely to detect the balancer being disabled

Requires HBase versions > 1.0 as older versions don't report the balancer being disabled in the UI

Tested on HBase 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckHBaseBalancerEnabled(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseBalancerEnabled, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['HBase Master', 'HBase']
        self.default_port = 16010
        self.path = '/master-status'
        self.auth = False
        self.json = False
        self.msg = 'HBase Balancer not defined yet'

    def add_options(self):
        super(CheckHBaseBalancerEnabled, self).add_options()

    def process_options(self):
        super(CheckHBaseBalancerEnabled, self).process_options()

    def parse(self, req):
        if 'Load Balancer is not enabled' in req.content:
            self.warning()
            self.msg = 'HBase balancer is not enabled!'
        else:
            self.ok()
            self.msg = 'HBase balancer is enabled'


if __name__ == '__main__':
    CheckHBaseBalancerEnabled().main()
