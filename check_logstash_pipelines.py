#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-11-24 21:10:35 +0100 (Fri, 24 Nov 2017)
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

Nagios Plugin to check the number of Logstash pipelines that are online via the Logstash Rest API

API is only available in Logstash 5.x onwards, will get connection refused on older versions.

Optional thresholds apply to the number of pipelines

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
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    #from harisekhon.utils import log
    from harisekhon.utils import ERRORS
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.6'


class CheckLogstashPipelines(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckLogstashPipelines, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Logstash'
        self.default_port = 9600
        # could add pipeline name to end of this endpoint but error would be less good 404 Not Found
        # Logstash 5.x /_node/pipeline <= use -5 switch for older Logstash
        # Logstash 6.x /_node/pipelines
        self.path = '/_node/pipelines'
        self.auth = False
        self.json = True
        self.msg = 'Logstash number of pipelines msg not defined yet'
        self.pipeline = None

    def add_options(self):
        super(CheckLogstashPipelines, self).add_options()
        self.add_opt('-5', '--logstash-5', action='store_true',
                     help='Logstash 5.x (has a slightly different API endpoint to 6.x)')
        self.add_opt('-l', '--list', action='store_true', help='List pipelines and exit (only for Logstash 6+)')
        self.add_thresholds(default_critical=1)

    def process_options(self):
        super(CheckLogstashPipelines, self).process_options()
        if self.get_opt('logstash_5'):
            self.path = self.path.rstrip('s')
            if self.get_opt('list'):
                self.usage('can only list pipelines for Logstash 6+')
        self.validate_thresholds(simple='lower', optional=True)

    def parse_json(self, json_data):
        num_pipelines = 0
        if self.get_opt('logstash_5'):
            pipeline = json_data['pipeline']
            if pipeline:
                num_pipelines = 1
        else:
            pipelines = json_data['pipelines']
            if self.get_opt('list'):
                print('Logstash Pipelines:\n')
                for pipeline in pipelines:
                    print(pipeline)
                sys.exit(ERRORS['UNKNOWN'])
            num_pipelines = len(pipelines)
        self.msg = "Logstash number of pipelines = '{}' ".format(num_pipelines)
        self.check_thresholds(num_pipelines)
        self.msg += ' | num_pipelines={}{}'.format(num_pipelines, self.get_perf_thresholds())


if __name__ == '__main__':
    CheckLogstashPipelines().main()
