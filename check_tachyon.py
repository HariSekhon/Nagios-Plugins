#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-02-02 17:46:18 +0000 (Tue, 02 Feb 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#  to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check a Tachyon Master/Worker is online

Queries the WebUI and displays the version and uptime

Optional --warn-on-recent-start raises WARNING if started within the last 30 mins in order to catch crashes that may
have been restarted by a supervisor process

Tested on Tachyon 0.7.1, 0.8.2

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import re
import sys
try:
    from bs4 import BeautifulSoup
    import requests
except ImportError as _:
    print(_)
    sys.exit(4)
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, prog
    from harisekhon.utils import validate_host, validate_port, isStr, isVersion, space_prefix
    from harisekhon import NagiosPlugin
except ImportError as _:
    print('module import failed: %s' % _, file=sys.stderr)
    print("Did you remember to build the project by running 'make'?", file=sys.stderr)
    print("Alternatively perhaps you tried to copy this program out without it's adjacent libraries?", file=sys.stderr)
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3.0'


class CheckTachyon(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckTachyon, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'Tachyon'
        name = ''
        default_port = None
        if re.search('master', prog, re.I):
            name = 'Master'
            default_port = 19999
        elif re.search('worker|slave', prog, re.I):
            name = 'Worker'
            default_port = 30000
        self.name = space_prefix(name)
        self.default_port = default_port

    def add_options(self):
        self.add_hostoption(name='%(software)s%(name)s' % self.__dict__,
                            default_host='localhost',
                            default_port=self.default_port)
        self.add_opt('--warn-on-recent-start', action='store_true', help='Raise WARNING if started in the last 30 mins')

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        warn_on_recent_start = self.get_opt('warn_on_recent_start')
        validate_host(host)
        validate_port(port)

        log.info('querying %s%s', self.software, self.name)
        url = 'http://%(host)s:%(port)s/home' % locals()
        log.debug('GET %s', url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            qquit('CRITICAL', _)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        if req.status_code != 200:
            qquit('CRITICAL', "%s %s" % (req.status_code, req.reason))
        soup = BeautifulSoup(req.content, 'html.parser')
        try:
            uptime = soup.find('th', text=re.compile('Uptime:?', re.I)).find_next_sibling().get_text()
            version = soup.find('th', text=re.compile('Version:?', re.I)).find_next_sibling().get_text()
        except (AttributeError, TypeError):
            qquit('UNKNOWN', 'failed to find parse %(software)s%(name)s uptime/version info' % self.__dict__)
        if not uptime or not isStr(uptime) or not re.search(r'\d+\s+second', uptime):
            qquit('UNKNOWN', '{0}{1} uptime format not recognized: {2}'.format(self.software, self.name, uptime))
        if not isVersion(version):
            qquit('UNKNOWN', '{0}{1} version format not recognized: {2}'.format(self.software, self.name, version))
        self.msg = '{0}{1} version: {2}, uptime: {3}'.format(self.software, self.name, version, uptime)  # pylint: disable=attribute-defined-outside-init
        self.ok()
        if warn_on_recent_start:
            match = re.match(r'^(\d+)\s+day[^\d\s]+\s+(\d+)\s+hour[^\d\s]+\s+(\d+)\s+minute', uptime, re.I)
            if match:
                days = int(match.group(1))
                hours = int(match.group(2))
                mins = int(match.group(3))
                if days == 0 and hours == 0 and mins < 30:
                    self.warning()
                    self.msg += ' (< 30 mins)'
            else:
                self.unknown()
                self.msg += " (couldn't determine if uptime < 30 mins)"


if __name__ == '__main__':
    CheckTachyon().main()
