#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-09-22 15:59:50 +0200 (Fri, 22 Sep 2017)
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

Nagios Plugin to check the version of a Presto SQL Coordinator via its API

Will return unknown if you try running it against a Presto worker as this information
isn't available via the Presto worker API

Tested on:

- Presto Facebook versions:               0.152, 0.157, 0.167, 0.179, 0.185, 0.186, 0.187, 0.188, 0.189
- Presto Teradata distribution versions:  0.152, 0.157, 0.167, 0.179
- back tested against all Facebook Presto releases 0.69, 0.71 - 0.189
  (see Presto docker images on DockerHub at https://hub.docker.com/u/harisekhon)

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
    from harisekhon.utils import UnknownError, support_msg_api
    from harisekhon import RestVersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


# pylint: disable=too-few-public-methods
class CheckPrestoVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPrestoVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Presto Coordinator', 'Presto']
        self.default_port = 8080
        self.path = '/v1/service/presto/general'
        self.json = True
        self.auth = False
        # allow version suffixes like -t-0.2 for Teradata Presto distribution
        self.lax_version = True

    # must override, cannot change to @staticmethod
    def parse_json(self, json_data):  # pylint: disable=no-self-use
        presto_service = None
        for service in json_data['services']:
            if service['type'] == 'presto':
                presto_service = service
        if not presto_service:
            raise UnknownError("'presto' service not found in list of services. " + \
                               "Check you haven't run this against a presto worker node as this information isn't " + \
                               "available via the worker API. Otherwise {0}".format(support_msg_api()))
        version = presto_service['properties']['node_version']
        # for presto <= 0.132 - presto-main:0.132 => 0.132
        version = version.split(':', 1)[-1]
        return version


if __name__ == '__main__':
    CheckPrestoVersion().main()
