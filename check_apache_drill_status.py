#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-02-18 18:44:59 +0000 (Thu, 18 Feb 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback # pylint: disable=line-too-long
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check Apache Drill's status page

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
try:
    from bs4 import BeautifulSoup
    import requests
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit
    from harisekhon.utils import validate_host, validate_port, support_msg
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckApacheDrillStatus(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckApacheDrillStatus, self).__init__()
        # Python 3.x
        # super().__init__()

    def add_options(self):
        self.add_hostoption(name='Apache Drill', default_host='localhost', default_port=8047)

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        validate_host(host)
        validate_port(port)

        url = 'http://%(host)s:%(port)s/status' % locals()
        log.debug('GET %s' % url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            qquit('CRITICAL', _)
        log.debug("response: %s %s" % (req.status_code, req.reason))
        log.debug("content:\n{0}\n{1}\n{2}".format('='*80, req.content.strip(), '='*80))
        if req.status_code != 200:
            qquit('CRITICAL', "%s %s" % (req.status_code, req.reason))
        soup = BeautifulSoup(req.content, 'html.parser')
        #if log.isEnabledFor(logging.DEBUG):
        #     log.debug("BeautifulSoup prettified:\n{0}\n{1}".format(soup.prettify(), '='*80))
        try:
            status = soup.find('div', { 'class': 'alert alert-success'}).get_text().strip()
        except (AttributeError, TypeError):
            qquit('UNKNOWN', 'failed to parse Apache Drill status page. %s' % support_msg())
        self.msg = "Apache Drill status = '{0}'".format(status)
        if re.match('Running!', status):
            self.ok()
        else:
            self.critical()


if __name__ == '__main__':
    CheckApacheDrillStatus().main()
