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

Nagios Plugin to check the HBase Balancer is enabled by parsing the HMaster JSP UI

Raises warning if the HBase Balancer isn't enabled

This has to parse the HMaster UI html tags for the warning, so this is brittle and
could break if there is an upstream change

Would prefer to get this out of the JMX but the info isn't available, see:

https://issues.apache.org/jira/browse/HBASE-20857

Requires HBase versions > 1.0 as older versions don't report the balancer being disabled in the UI

Tested on HBase 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

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
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


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
        soup = BeautifulSoup(req.content, 'html.parser')
        if log.isEnabledFor(logging.DEBUG):
            log.debug("BeautifulSoup prettified:\n{0}\n{1}".format(soup.prettify(), '='*80))
        link = soup.find('div', {'class': 'alert alert-warning'}, text=re.compile('balancer', re.I))
        if link is None:
            self.ok()
            self.msg = 'HBase balancer is enabled'
        else:
            self.warning()
            text = link.get_text()
            text = ' '.join([_.strip() for _ in text.split('\n')])
            self.msg = 'HBase balancer is not enabled! {}'.format(text)


if __name__ == '__main__':
    CheckHBaseBalancerEnabled().main()
