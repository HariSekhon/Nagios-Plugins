#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-11-01 20:02:20 +0100 (Wed, 01 Nov 2017)
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

Nagios Plugin to check a Tachyon Worker's last heartbeat to the Master

Thresholds apply to the number of seconds since last heartbeat to master

Under normal operation this usually shows 0 secs indicating a heartbeat was received in the last second

Tested on Tachyon 0.7.1, 0.8.2

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import sys
try:
    from bs4 import BeautifulSoup
except ImportError as _:
    print(_)
    sys.exit(4)
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import ERRORS, UnknownError, CriticalError, validate_host, isInt, support_msg, code_error
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print('module import failed: %s' % _, file=sys.stderr)
    print("Did you remember to build the project by running 'make'?", file=sys.stderr)
    print("Alternatively perhaps you tried to copy this program out without it's adjacent libraries?", file=sys.stderr)
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.1'


class CheckTachyonWorkerHeartbeat(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckTachyonWorkerHeartbeat, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'Tachyon'
        self.name = ['Tachyon Master', 'Tachyon']
        self.default_port = 19999
        self.path = '/workers'
        self.node = None
        self.auth = False
        self.msg = '{0} message not defined'.format(self.name)

    def add_options(self):
        super(CheckTachyonWorkerHeartbeat, self).add_options()
        self.add_opt('-N', '--node', help='{0} Worker Node Name as it appears in the UI'.format(self.software))
        self.add_opt('-l', '--list', action='store_true', help='List nodes and exit')
        self.add_thresholds(default_warning=10, default_critical=60)

    def process_options(self):
        super(CheckTachyonWorkerHeartbeat, self).process_options()
        if not self.get_opt('list'):
            self.node = self.get_opt('node')
            validate_host(self.node, 'node')
        self.validate_thresholds()

    def list_workers(self, soup):
        if self.get_opt('list'):
            print('{0} Worker Nodes:\n'.format(self.software))
            for row in soup.find('tbody').find_all('tr'):
                worker = row.find_next().get_text()
                print(worker)
            sys.exit(ERRORS['UNKNOWN'])

    def parse(self, req):
        soup = BeautifulSoup(req.content, 'html.parser')
        last_heartbeat = None
        try:
            self.list_workers(soup)
            heartbeat_col_header = soup.find('th', text='Node Name').find_next_sibling().get_text()
            # make sure ordering of columns is as we expect so we're parsing the correct number for heartbeat lag
            if heartbeat_col_header != 'Last Heartbeat':
                code_error("heartbeat column header '{}' != Last Heartbeat".format(heartbeat_col_header))
            last_heartbeat = soup.find('th', text=self.node).find_next_sibling().get_text()
            if last_heartbeat is None:
                raise AttributeError
        except (AttributeError, TypeError):
            raise CriticalError("{0} worker '{1}' not found among list of live workers!"\
                                .format(self.software, self.node))
        if not isInt(last_heartbeat):
            raise UnknownError("last heartbeat '{0}' for node '{1}' is not an integer, possible parsing error! {2}"\
                               .format(last_heartbeat, self.node, support_msg()))
        self.msg = "{0} worker '{1}' last heartbeat = {2} secs ago".format(self.software, self.node, last_heartbeat)
        self.check_thresholds(last_heartbeat)
        self.msg += ' | last_heartbeat={0}s{1}'.format(last_heartbeat, self.get_perf_thresholds())


if __name__ == '__main__':
    CheckTachyonWorkerHeartbeat().main()
