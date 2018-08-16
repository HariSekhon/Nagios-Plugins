#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-06-20 17:24:55 +0200 (Tue, 20 Jun 2017)
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

Nagios Plugin to check the status of an Atlas metadata server instance via the HTTP Rest API

By default it expects Atlas to be in an active state, for --high-availability setups it will permit a passive state.

If you want to ensure at least one of the Atlas servers is active you can either check a load balancer endpoint or
combine this check with find_active_server.py from DevOps Python Tools (see project README.md for more details).

This plugin will raise a Warning if the Atlas instance is transitioning between active and passive states
as that means a failover is occurring.

Tested on Atlas 0.8.0 on Hortonworks HDP 2.6.0

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
__version__ = '0.6.0'


class CheckAtlasStatus(StatusNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAtlasStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Atlas'
        self.default_port = 21000
        self.protocol = 'http'
        self.high_availability = False
        self.ok()

    def add_options(self):
        super(CheckAtlasStatus, self).add_options()
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')
        self.add_opt('-A', '--high-availability', action='store_true',
                     help='High Availability setup, allow either ACTIVE or PASSIVE status')

    def process_options(self):
        super(CheckAtlasStatus, self).process_options()
        self.high_availability = self.get_opt('high_availability')

    def get_status(self):
        if self.get_opt('ssl'):
            self.protocol = 'https'
        url = '%(protocol)s://%(host)s:%(port)s/api/atlas/admin/status' % self.__dict__
        req = RequestHandler().get(url)
        return self.parse(req)

    def get_key(self, json_data, key):
        try:
            return json_data[key]
        except KeyError:
            raise UnknownError('\'{0}\' key was not returned in output from '.format(key) +
                               'Atlas metadata server instance at {0}:{1}. {2}'\
                               .format(self.host, self.port, support_msg_api()))

    def parse(self, req):
        if not isJson(req.content):
            raise UnknownError('non-JSON returned by Atlas metadata server instance at {0}:{1}'\
                               .format(self.host, self.port))
        _ = json.loads(req.content)
        status = self.get_key(_, 'Status')
        if status == 'ACTIVE':
            pass
        elif self.high_availability and status == 'PASSIVE':
            pass
        elif status in ('BECOMING_ACTIVE', 'BECOMING_PASSIVE'):
            self.warning()
        else:
            self.critical()
        return status


if __name__ == '__main__':
    CheckAtlasStatus().main()
