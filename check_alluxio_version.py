#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-05-23 17:49:21 +0100 (Mon, 23 May 2016)
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

Nagios Plugin to check the deployed version of Alluxio matches what's expected.

This is also used in the accompanying test suite to ensure we're checking the right version of Alluxio
for compatibility for all my other Alluxio nagios plugins.

Tested on Alluxio 1.0.0, 1.0.1, 1.1.0

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
    from check_tachyon_version import CheckTachyonVersion
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'

# pylint: disable=too-few-public-methods


class CheckAlluxioVersion(CheckTachyonVersion):

    def __init__(self):
        # Python 2.x
        super(CheckAlluxioVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'Alluxio{0}'.format(self.name)

if __name__ == '__main__':
    CheckAlluxioVersion().main()
