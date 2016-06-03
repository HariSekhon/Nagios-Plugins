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

Nagios Plugin to check the number of live Tachyon workers via the Tachyon Master UI

TODO: thresholds on number of live workers (coming soon)

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
    from harisekhon.utils import log, qquit
    from harisekhon.utils import validate_host, validate_port
    from harisekhon import NagiosPlugin
except ImportError as _:
    print('module import failed: %s' % _, file=sys.stderr)
    print("Did you remember to build the project by running 'make'?", file=sys.stderr)
    print("Alternatively perhaps you tried to copy this program out without it's adjacent libraries?", file=sys.stderr)
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckTachyonRunningWorkers(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckTachyonRunningWorkers, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'Tachyon'

    def add_options(self):
        self.add_hostoption(name='%s Master' % self.software,
                            # TODO: ['Tachyon Master', 'Tachyon']. add_hostopt
                            default_host='localhost',
                            default_port=19999)

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        validate_host(host)
        validate_port(port)

        log.info('querying %s Master', self.software)
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
            running_workers = soup.find('th', text=re.compile(r'Running\s+Workers:?', re.I))\
                .find_next_sibling().get_text()
        except (AttributeError, TypeError):
            qquit('UNKNOWN', 'failed to find parse %s Master info for running workers' % self.software)
        try:
            running_workers = int(running_workers)
        except (ValueError, TypeError):
            qquit('UNKNOWN', '{0} Master live workers parsing returned non-integer: {1}'.
                  format(self.software, running_workers))
        self.msg = '{0} running workers = {1}'.format(self.software, running_workers)  # pylint: disable=attribute-defined-outside-init
        self.ok()
        # TODO: thresholds on number of live workers (coming soon)
        if running_workers < 1:
            self.critical()


if __name__ == '__main__':
    CheckTachyonRunningWorkers().main()
