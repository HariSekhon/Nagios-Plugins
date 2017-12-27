#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-11-24 19:53:59 +0100 (Fri, 24 Nov 2017)
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

Nagios Plugin to check the version of Logstash via its Rest API

API is only available in Logstash 5.x onwards, will get connection refused on older versions

Ensure Logstash options:
  --http.host should be set to 0.0.0.0 if querying remotely
  --http.port should be set to the same port that you are querying via this plugin's --port switch

Tested on Logstash versions 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1

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
    #from harisekhon.utils import support_msg_api
    from harisekhon import RestVersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckLogstashVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckLogstashVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Logstash'
        self.default_port = 9600
        self.path = '/'
        self.json = True
        self.auth = False
        self.json_data = None
        self.ok()

    def parse_json(self, json_data):
        # for extra_info() to pick up, tried changing this through frameworks but none of the methods are elegant, this
        # is the simplest without double parsing or requiring too many changes across 2 parent classes
        self.json_data = json_data
        version = json_data['version']
        version = version.split('-')[0]
        if not self.verbose:
            version = '.'.join(version.split('.')[0:3])
        return version

    def extra_info(self):
        msg = ''
        if self.verbose:
            build_date = self.json_data['build_date']
            msg = ', build date: {}'.format(build_date)
        return msg


if __name__ == '__main__':
    CheckLogstashVersion().main()
