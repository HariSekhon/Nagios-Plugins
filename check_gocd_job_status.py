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

Nagios Plugin to check GoCD job status via the GoCD server API

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


class CheckGoCDJobStatus(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckGoCDJobStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'GoCD'
        self.default_port = 8153
        self.path = '/go/api/jobs'
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
        super(CheckGoCDJobStatus, self).add_options()
        self.add_opt('-i', '--pipeline', help='Pipeline of job')
        self.add_opt('-s', '--stage', help='Stage of job')
        self.add_opt('-j', '--job', help='Job name')

    def process_options(self):
        super(CheckGoCDJobStatus, self).process_options()
        self.pipeline = self.get_opt('pipeline')
        self.stage = self.get_opt('stage')
        self.job = self.get_opt('job')
        validate_chars(self.pipeline, 'pipeline', 'A-Za-z0-9-')
        validate_chars(self.stage, 'stage', 'A-Za-z0-9-')
        validate_chars(self.job, 'job', 'A-Za-z0-9-')
        self.path += '/{pipeline}/{stage}/{job}/history'.format(
            pipeline=self.pipeline,
            stage=self.stage,
            job=self.job)

    def parse_json(self, json_data):
        jobs = json_data['jobs']
        job = None
        if not jobs:
            raise UnknownError('no jobs found - did you specify correct --pipeline / --stage / --job?')
        for _ in jobs:
            if _['state'] in ('Scheduled', 'Building'):
                continue
            job = _
            break
        self.msg = "GoCD pipeline '{pipeline}' stage '{stage}' job '{job}' last build = "\
                   .format(pipeline=self.pipeline, stage=self.stage, job=self.job)
        if not job:
            self.msg += 'Unknown (no jobs completed recently)'
            self.unknown()
            return
        result = job['result']
        self.msg += result
        if result != 'Passed':
            self.critical()


if __name__ == '__main__':
    CheckGoCDJobStatus().main()
