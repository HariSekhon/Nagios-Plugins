#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-05-23 17:49:21 +0100 (Mon, 23 May 2016)
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

Nagios Plugin to check the deployed version of Tachyon matches what's expected.

This is also used in the accompanying test suite to ensure we're checking the right version of Tachyon
for compatibility for all my other Tachyon nagios plugins.

Tested on Tachyon 0.7.1, 0.8.2

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
    from harisekhon.utils import log, qquit, support_msg_api, prog, space_prefix
    from harisekhon import VersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'

# pylint: disable=too-few-public-methods


class CheckTachyonVersion(VersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckTachyonVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ''
        if re.search('master', prog, re.I):
            self.name = 'Master'
            self.default_port = 19999
        elif re.search('worker|slave', prog, re.I):
            self.name = 'Worker'
            self.default_port = 30000
        else:
            self.default_port = None
        self.name = space_prefix(self.name)
        self.software = 'Tachyon{0}'.format(self.name)

    def get_version(self):
        log.info('querying %s', self.software)
        url = 'http://{host}:{port}/home'.format(host=self.host, port=self.port)
        log.debug('GET %s', url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            qquit('CRITICAL', _)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        if req.status_code != 200:
            qquit('CRITICAL', "{0} {1}".format(req.status_code, req.reason))
        soup = BeautifulSoup(req.content, 'html.parser')
        if log.isEnabledFor(logging.DEBUG):
            log.debug("BeautifulSoup prettified:\n{0}\n{1}".format(soup.prettify(), '='*80))
        try:
            version = soup.find('th', text='Version:').find_next('th').text
        except (AttributeError, TypeError) as _:
            qquit('UNKNOWN', 'failed to find parse {0} output. {1}\n{2}'\
                             .format(self.software, support_msg_api(), traceback.format_exc()))
        return version


if __name__ == '__main__':
    CheckTachyonVersion().main()
