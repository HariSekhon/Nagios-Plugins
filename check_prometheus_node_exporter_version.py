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

Nagios Plugin to check the version of a Prometheus Node Exporter scrape target

Tested on Prometheus Node Exporter 0.12, 0.13, 0.14, 0.15

(0.9.0 does not contain this build information)

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

#import json
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
    #from harisekhon.utils import log, UnknownError, version_regex
    from harisekhon.utils import version_regex
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckPrometheusNodeExporterVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPrometheusNodeExporterVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Prometheus Node Exporter', 'Node Exporter']
        self.default_port = 9100
        self.path = '/metrics'
        self.auth = False
        self.json = False
        self.msg = self.name[0] + ' '

    # pylint: disable=no-self-use
    def parse(self, req):
        version = None
        regex = re.compile(r'^node_exporter_build_info({.+,version="(%s)"})\s+\d+$' % version_regex)
        for line in req.content.split('\n'):
            match = regex.match(line)
            if match:
                version = match.group(2)
                #raw_json = match.group(1)
                #log.debug('raw json string: %s', raw_json)
                #try:
                    # doesn't parse as the keys are unquoted
                    #json_data = json.loads(raw_json)
                    #version = json_data['version']
                #except (KeyError, ValueError) as _:
                #    raise UnknownError('json parse failure on node_exporter_build_info: {}'.format(_))
        return version


if __name__ == '__main__':
    CheckPrometheusNodeExporterVersion().main()
