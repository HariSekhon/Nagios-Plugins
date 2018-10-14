#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-09-25 12:21:49 +0100 (Sun, 25 Sep 2016)
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

Nagios Plugin to check the deployed version of an HBase HRegionserver matches what's expected.

This is also used in the accompanying test suite to ensure we're checking the right version of HBase
for compatibility for all my other HBase nagios plugins.

Tested on Apache HBase 0.92, 0.94, 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from check_hbase_master_version import CheckHBaseMasterVersion
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckHBaseRegionserverVersion(CheckHBaseMasterVersion):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseRegionserverVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'HBase RegionServer'
        # 16301 on standalone
        self.default_port = 16030
        self.url_path = 'rs-status'


if __name__ == '__main__':
    CheckHBaseRegionserverVersion().main()
