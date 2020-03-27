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

Nagios Plugin to check GoCD stage status via the GoCD server API

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
    from harisekhon.utils import validate_chars, UnknownError
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckGoCDStageStatus(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckGoCDStageStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'GoCD'
        self.default_port = 8153
        self.path = '/go/api/stages'
        self.headers = {
            'Accept': 'application/vnd.go.cd.v1+json'
        }
        self.auth = 'optional'
        self.json = True
        self.pipeline = None
        self.stage = None
        self.stage = None
        self.msg = 'GoCD msg not defined yet'

    def add_options(self):
        super(CheckGoCDStageStatus, self).add_options()
        self.add_opt('-i', '--pipeline', help='Pipeline of stage')
        self.add_opt('-s', '--stage', help='Stage of stage')

    def process_options(self):
        super(CheckGoCDStageStatus, self).process_options()
        self.pipeline = self.get_opt('pipeline')
        self.stage = self.get_opt('stage')
        validate_chars(self.pipeline, 'pipeline', 'A-Za-z0-9-')
        validate_chars(self.stage, 'stage', 'A-Za-z0-9-')
        self.path += '/{pipeline}/{stage}/history'.format(
            pipeline=self.pipeline,
            stage=self.stage)

    def parse_json(self, json_data):
        stages = json_data['stages']
        stage = None
        if not stages:
            raise UnknownError('no stages found - did you specify correct --pipeline / --stage?')
        for _ in stages:
            if not self.jobs_finished(_):
                continue
            stage = _
            break
        self.msg = "GoCD pipeline '{pipeline}' stage '{stage}' last build = "\
                   .format(pipeline=self.pipeline, stage=self.stage)
        if not stage:
            self.msg += 'Unknown (no stages completed recently)'
            self.unknown()
            return
        result = stage['result']
        self.msg += result
        if result != 'Passed':
            self.critical()

    @staticmethod
    def jobs_finished(stage):
        jobs = stage['jobs']
        for job in jobs:
            if job['state'] in ('Scheduled', 'Building'):
                return False
        return True


if __name__ == '__main__':
    CheckGoCDStageStatus().main()
