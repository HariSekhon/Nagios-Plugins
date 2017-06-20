#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-25 10:11:51 +0000 (Mon, 25 Jan 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check the status of an Oozie server via the HTTP Rest API

Tested on Oozie 4.2.0 on Hortonworks HDP 2.3.2, 2.4.0, 2.6.0

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import json
import os
import sys
import traceback
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import UnknownError, support_msg_api
    from harisekhon.utils import isJson
    from harisekhon import RequestHandler
    from harisekhon import StatusNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.5'


class CheckOozieStatus(StatusNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckOozieStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Oozie'
        self.default_port = 11000
        self.protocol = 'http'

    def add_options(self):
        super(CheckOozieStatus, self).add_options()
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')

    def get_status(self):
        if self.get_opt('ssl'):
            self.protocol = 'https'
        url = '%(protocol)s://%(host)s:%(port)s/oozie/v1/admin/status' % self.__dict__
        req = RequestHandler().get(url)
        return self.parse(req)

    def parse(self, req):
        if not isJson(req.content):
            raise UnknownError('non-JSON returned by Oozie server at {0}:{1}'.format(self.host, self.port))
        status = None
        try:
            _ = json.loads(req.content)
            status = _['systemMode']
        except KeyError:
            raise UnknownError('\'systemMode\' key was not returned in output from Oozie at {0}:{1}. {2}'\
                               .format(self.host, self.port, support_msg_api()))
        if status == 'NORMAL':
            self.ok()
        else:
            self.critical()
        return status


if __name__ == '__main__':
    CheckOozieStatus().main()
