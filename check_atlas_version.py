#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-06-20 22:47:59 +0200 (Tue, 20 Jun 2017)
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

Nagios Plugin to check the version of Atlas via the Rest API

Tested on Atlas 0.8.0 on Hortonworks HDP 2.6.0

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
    from harisekhon.utils import UnknownError
    from harisekhon import RestVersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


# pylint: disable=too-few-public-methods
class CheckAtlasVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAtlasVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Atlas'
        self.default_port = 21000
        self.path = '/api/atlas/admin/version'
        self.json = True
        self.ok()

    def parse_json(self, json_data):
        if json_data['Name'] != 'apache-atlas':
            raise UnknownError('Name {} != apache-atlas'.format(json_data['Name']))
        version = json_data['Version']
        version = version.split('-')[0]
        if not self.verbose:
            version = '.'.join(version.split('.')[0:3])
        return version


if __name__ == '__main__':
    CheckAtlasVersion().main()
