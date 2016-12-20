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

Nagios Plugin to check RabbitMQ stats db event queue size via the Management REST API

Requires the management plugin to be loaded.

Optional thresholds may be applied, perfdata is output regardless.

Tested on RabbitMQ 3.5.7, 3.6.6 (does not work on RabbitMQ <= 3.4)

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
    from harisekhon.utils import isInt, UnknownError, support_msg_api
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckRabbitMQVersion(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckRabbitMQVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'RabbitMQ'
        self.default_port = 15672
        self.default_user = 'guest'
        self.default_password = 'guest'
        self.path = 'api/overview'
        self.json = True
        self.msg = 'msg not defined yet'

    def add_options(self):
        super(CheckRabbitMQVersion, self).add_options()
        self.add_thresholds()

    def process_options(self):
        super(CheckRabbitMQVersion, self).process_options()
        self.validate_thresholds(optional=True)

    def parse_json(self, json_data):
        stats_db_event_queue = json_data['statistics_db_event_queue']
        if not isInt(stats_db_event_queue):
            raise UnknownError("non-integer stats db event queue returned ('{0}'). {1}"\
                               .format(stats_db_event_queue, support_msg_api()))
        stats_db_event_queue = int(stats_db_event_queue)
        self.msg = "{0} stats dbs event queue = {1}".format(self.name, stats_db_event_queue)
        self.check_thresholds(stats_db_event_queue)
        self.msg += " | stats_db_event_queue={0}".format(stats_db_event_queue)
        self.msg += self.get_perf_thresholds()


if __name__ == '__main__':
    CheckRabbitMQVersion().main()
