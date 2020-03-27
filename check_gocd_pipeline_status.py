#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-03-27 22:34:24 +0000 (Fri, 27 Mar 2020)
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

Nagios Plugin to check GoCD pipeline status via the GoCD server API

Tested on GoCD 20.2.0

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
    from harisekhon.utils import validate_chars
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckGoCDPipelineStatus(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckGoCDPipelineStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'GoCD'
        self.default_port = 8153
        self.path = '/go/api/pipelines'
        self.headers = {
            'Accept': 'application/vnd.go.cd.v1+json'
        }
        self.auth = 'optional'
        self.json = True
        self.pipeline = None
        self.stage = None
        self.job = None
        self.msg = 'GoCD msg not defined yet'

    def add_options(self):
        super(CheckGoCDPipelineStatus, self).add_options()
        self.add_opt('-i', '--pipeline', help='Pipeline of job')

    def process_options(self):
        super(CheckGoCDPipelineStatus, self).process_options()
        self.pipeline = self.get_opt('pipeline')
        validate_chars(self.pipeline, 'pipeline', 'A-Za-z0-9-')
        self.path += '/{pipeline}/history'.format(pipeline=self.pipeline)

    def parse_json(self, json_data):
        pipelines = json_data['pipelines']
        pipeline = None
        for _ in pipelines:
            if not self.pipeline_finished(_):
                continue
            pipeline = _
        self.msg = "GoCD pipeline '{pipeline}' passed = ".format(pipeline=self.pipeline)
        if not pipeline:
            self.msg += 'Unknown (no pipelines completed recently)'
            self.unknown()
            return
        result = self.pipeline_passed(pipeline)
        self.msg += '{}'.format(result)
        if not result:
            self.critical()

    @staticmethod
    def pipeline_finished(pipeline):
        stages = pipeline['stages']
        for stage in stages:
            if stage['status'] in ('Scheduled', 'Building'):
                return False
        return True

    @staticmethod
    def pipeline_passed(pipeline):
        stages = pipeline['stages']
        for stage in stages:
            if stage['status'] != 'Passed':
                return False
            if stage['result'] != 'Passed':
                return False
        return True


if __name__ == '__main__':
    CheckGoCDPipelineStatus().main()
