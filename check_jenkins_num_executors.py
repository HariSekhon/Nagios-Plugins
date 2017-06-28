#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-06-27 23:14:03 +0200 (Tue, 27 Jun 2017)
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

Nagios Plugin to check the number of executors of a Jenkins server

Thresholds may be optionally applied using --warning/--critical for minimum number of executors or range format

The --password switch accepts either a password or an API token

Tested on Jenkins 2.60.1

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
    from harisekhon.utils import isInt, UnknownError, support_msg_api
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckJenkinsNumExecutors(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsNumExecutors, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Jenkins'
        self.default_port = 8080
        self.path = '/api/json'
        self.json = True
        self.msg = self.name + ' number of executors = '

    def add_options(self):
        super(CheckJenkinsNumExecutors, self).add_options()
        self.add_thresholds()

    def process_options(self):
        super(CheckJenkinsNumExecutors, self).process_options()
        self.validate_thresholds(simple='lower', optional=True)

    def parse_json(self, json_data):
        num_executors = json_data['numExecutors']
        if not isInt(num_executors):
            raise UnknownError('non-integer returned by Jenkins. {0}'.format(support_msg_api()))
        self.msg += '{:d}'.format(num_executors)
        self.check_thresholds(num_executors)
        self.msg += ' | num_executors={0:d}'.format(num_executors)
        self.msg += self.get_perf_thresholds(boundary='lower')


if __name__ == '__main__':
    CheckJenkinsNumExecutors().main()
