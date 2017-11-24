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

Nagios Plugin to check a Logstash pipeline is configured via its Rest API

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
    #from harisekhon.utils import CriticalError, UnknownError
    from harisekhon.utils import ERRORS, validate_chars
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckLogstashPipeline(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckLogstashPipeline, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Logstash'
        self.default_port = 9600
        self.path = '/_node/pipelines'
        self.auth = False
        self.json = True
        self.msg = 'Logstash piplines msg not defined yet'
        self.pipeline = None
        self.list_pipelines = False

    def add_options(self):
        super(CheckLogstashPipeline, self).add_options()
        self.add_opt('-i', '--pipeline', help='Pipeline to expect is configured (default: main)')
        self.add_opt('-l', '--list', action='store_true', help='List pipelines and exit')

    def process_options(self):
        super(CheckLogstashPipeline, self).process_options()
        self.pipeline = self.get_opt('pipeline')
        if not self.pipeline:
            self.pipeline = 'main'
        validate_chars(self.pipeline, 'pipeline', 'A-Za-z0-9_-')
        self.list_pipelines = self.get_opt('list')

    def parse_json(self, json_data):
        pipelines = json_data['pipelines']
        if self.list_pipelines:
            print('Logstash Pipelines:\n')
            for pipeline in pipelines:
                print(pipeline)
            sys.exit(ERRORS['UNKNOWN'])
        self.msg = "Logstash pipeline '{}' ".format(self.pipeline)
        if self.pipeline in pipelines:
            self.msg += 'exists'
        else:
            self.critical()
            self.msg += 'does not exist!'


if __name__ == '__main__':
    CheckLogstashPipeline().main()
