#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-01-30 11:57:10 +0000 (Tue, 30 Jan 2018)
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

Nagios Plugin to check the version of a Prometheus Collectd scrape target

This should be targeted against Collectd's write_prometheus plugin

Tested on Collectd 5.8

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import re
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import RestVersionNagiosPlugin
    from harisekhon.utils import version_regex
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckPrometheusCollectdVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPrometheusCollectdVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Prometheus Collectd', 'Collectd']
        self.default_port = 9103
        # should technically be /metrics but / works too
        self.path = '/metrics'
        self.auth = False
        self.json = False
        self.msg = self.name[0] + ' '

    # pylint: disable=no-self-use
    def parse(self, req):
        match = re.search('# collectd/write_prometheus ({}) '.format(version_regex), req.content)
        version = None
        if match:
            version = match.group(1)
        return version


if __name__ == '__main__':
    CheckPrometheusCollectdVersion().main()
