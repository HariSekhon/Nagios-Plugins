#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-11-25 20:29:31 +0100 (Sat, 25 Nov 2017)
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

Nagios Plugin to check a Logstash instance is online via its Rest API

Outputs uptime which may have optional thresholds applied to alert on logstash restarts
(to detect crashing / respawning processes such as can happen with Java Heap dumps)

This check's API endpoint for JVM info for uptime can take an extra 30-40 secs to come online
for a faster check that will return OK within a few secs of Logstash starting see check_logstash_version.py

API is only available in Logstash 5.x onwards, will get connection refused on older versions

Ensure Logstash options:
  --http.host should be set to 0.0.0.0 if querying remotely
  --http.port should be set to the same port that you are querying via this plugin's --port switch

Tested on Logstash 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import time
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import sec2human
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckLogstashStatus(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckLogstashStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Logstash'
        self.default_port = 9600
        # could add pipeline name to end of this endpoint but error would be less good 404 Not Found
        # Logstash 5.x /_node/pipeline <= use -5 switch for older Logstash
        # Logstash 6.x /_node/pipelines
        self.path = '/_node/jvm'
        self.auth = False
        self.json = True
        self.msg = 'Logstash status msg not defined yet'

    def add_options(self):
        super(CheckLogstashStatus, self).add_options()
        self.add_thresholds(default_warning=90)

    def process_options(self):
        super(CheckLogstashStatus, self).process_options()
        self.validate_thresholds(simple='lower', optional=True)

    def parse_json(self, json_data):
        jvm = json_data['jvm']
        start_millis = jvm['start_time_in_millis']
        uptime_secs = time.time() - (start_millis/1000)
        self.msg = 'Logstash online, uptime: {}'.format(sec2human(uptime_secs))
        self.msg += ' [{0:.0f} secs]'.format(uptime_secs)
        self.check_thresholds(uptime_secs)
        if self.verbose:
            pid = jvm['pid']
            self.msg += ', pid: {}'.format(pid)


if __name__ == '__main__':
    CheckLogstashStatus().main()
