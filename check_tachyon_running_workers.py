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

Tested on Tachyon 0.7, 0.8

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
except ImportError as _:
    print(_)
    sys.exit(4)
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, UnknownError
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print('module import failed: %s' % _, file=sys.stderr)
    print("Did you remember to build the project by running 'make'?", file=sys.stderr)
    print("Alternatively perhaps you tried to copy this program out without it's adjacent libraries?", file=sys.stderr)
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4.0'


class CheckTachyonRunningWorkers(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckTachyonRunningWorkers, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Tachyon Master', 'Tachyon']
        self.software = 'Tachyon'
        self.default_port = 19999
        self.path = '/home'
        self.auth = False
        self.json = False
        self.msg = 'Tachyon msg not defined'

    def add_options(self):
        super(CheckTachyonRunningWorkers, self).add_options()
        self.add_thresholds(default_critical=1)

    def process_options(self):
        super(CheckTachyonRunningWorkers, self).process_options()
        self.validate_thresholds(simple='lower')

    def parse(self, req):
        soup = BeautifulSoup(req.content, 'html.parser')
        try:
            log.info('parsing %s page for number of running workers', self.path)
            running_workers = soup.find('th', text=re.compile(r'Running\s+Workers:?', re.I))\
                .find_next_sibling().get_text()
        except (AttributeError, TypeError):
            raise UnknownError('failed to find parse {0} Master info for running workers'.format(self.software))
        try:
            running_workers = int(running_workers)
        except (ValueError, TypeError):
            raise UnknownError('{0} Master live workers parsing returned non-integer: {1}'.
                               format(self.software, running_workers))
        self.msg = '{0} running workers = {1}'.format(self.software, running_workers)
        self.check_thresholds(running_workers)
        self.msg += ' | '
        self.msg += 'running_workers={0}{1}'.format(running_workers, self.get_perf_thresholds())


if __name__ == '__main__':
    CheckTachyonRunningWorkers().main()
