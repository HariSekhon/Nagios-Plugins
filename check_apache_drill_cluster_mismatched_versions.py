#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-05-04 18:34:48 +0100 (Fri, 04 May 2018)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback # pylint: disable=line-too-long
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check an Apache Drill cluster for any mismatched versions via the Rest API of any drill node

Recommend to combine this with the Drill HAProxy config from the haproxy/ directory
to run this via any node in the cluster (or combine with find_active_apache_drill.py, see README)

Tested on Apache Drill 1.10, 1.11, 1.12, 1.13, 1.14, 1.15

(API endpoint is not available in Apache Drill versions < 1.10)

"""

# Doesn't work on 0.7, the API endpoint isn't found

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckApacheDrillClusterMismatchedVersions(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckApacheDrillClusterMismatchedVersions, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Apache Drill'
        self.path = '/cluster.json'
        self.default_port = 8047
        self.json = True
        self.auth = False
        self.msg = 'Apache Drill message not defined'

    def parse_json(self, json_data):
        mismatched_versions = json_data['mismatchedVersions']
        if mismatched_versions:
            self.warning()
        else:
            mismatched_versions = None
        self.msg = 'Apache Drill mismatched versions = {}'.format(mismatched_versions)


if __name__ == '__main__':
    CheckApacheDrillClusterMismatchedVersions().main()
