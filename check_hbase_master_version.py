#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-09-25 12:21:49 +0100 (Sun, 25 Sep 2016)
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

Nagios Plugin to check the deployed version of an HBase HMaster matches what's expected.

This is also used in the accompanying test suite to ensure we're checking the right version of HBase
for compatibility for all my other HBase nagios plugins.

Tested on Apache HBase 0.92, 0.94, 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
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
    from harisekhon.utils import log, qquit, support_msg
    from harisekhon import VersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckHBaseMasterVersion(VersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseMasterVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'HBase Master'
        self.default_port = 16010
        self.url_path = 'master-status'

    def get_version(self):
        url = 'http://{host}:{port}/{path}'.format(host=self.host, port=self.port, path=self.url_path)
        log.debug('GET %s', url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            qquit('CRITICAL', _)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        if req.status_code != 200:
            qquit('CRITICAL', '%s %s' % (req.status_code, req.reason))
        soup = BeautifulSoup(req.content, 'html.parser')
        if log.isEnabledFor(logging.DEBUG):
            log.debug('BeautifulSoup prettified:\n{0}\n{1}'.format(soup.prettify(), '='*80))
        version = self.parse_version(soup)
        return version

    def parse_version(self, soup):
        version = None
        try:
            attributes_table = soup.find('table', {'id':'attributes_table'})
            rows = attributes_table.findAll('tr')
            num_rows = len(rows)
            self.sanity_check(num_rows > 5, 'too few rows ({0})'.format(num_rows))
            headers = rows[0].findAll('th')
            num_headers = len(headers)
            self.sanity_check(num_headers > 2, 'too few header columns ({0})'.format(num_headers))
            self.sanity_check(headers[0].text.strip() == 'Attribute Name',
                              'header first column does not match expected \'Attribute Name\'')
            self.sanity_check(headers[1].text.strip() == 'Value',
                              'header second column does not match expected \'Value\'')
            for row in rows:
                cols = row.findAll('td')
                num_cols = len(cols)
                if num_cols == 0:
                    continue
                self.sanity_check(num_cols > 2, 'too few columns ({0})'.format(num_cols))
                if cols[0].text.strip() == 'HBase Version':
                    version = cols[1].text.split(',')[0]
                    break
        except (AttributeError, TypeError):
            qquit('UNKNOWN', 'failed to find parse HBase output. {0}\n{1}'\
                             .format(support_msg(), traceback.format_exc()))
        # strip things like -hadoop2 at end
        version = version.split('-')[0]
        return version

    @staticmethod
    def sanity_check(condition, msg):
        if not condition:
            qquit('UNKNOWN', 'HBase attribute table header ' +
                  msg + ', failed sanity check! ' + support_msg())


if __name__ == '__main__':
    CheckHBaseMasterVersion().main()
