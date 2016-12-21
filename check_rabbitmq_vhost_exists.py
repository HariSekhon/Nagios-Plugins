#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-20 17:30:59 +0000 (Tue, 20 Dec 2016)
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

Nagios Plugin to check a given RabbitMQ vhost exists via the RabbitMQ Management REST API

Requires the management plugin to be loaded.

Verbose mode will output whether tracing is enabled on the vhost, and an optional --no-tracing check can
be enabled to ensure that tracing is set to False or raise a Warning status otherwise

Tested on RabbitMQ 3.4.4, 3.5.7, 3.6.6

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
    from harisekhon.utils import getenvs, isList, validate_chars, \
                                 UnknownError, support_msg_api
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckRabbitMQVhost(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckRabbitMQVhost, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'RabbitMQ'
        self.default_port = 15672
        self.default_user = 'guest'
        self.default_password = 'guest'
        self.default_vhost = '/'
        self.vhost = self.default_vhost
        self.no_tracing = None
        self.path = 'api/vhosts'
        self.json = True
        self.msg = 'msg not defined yet'

    def add_options(self):
        super(CheckRabbitMQVhost, self).add_options()
        self.add_opt('-O', '--vhost', default=getenvs('RABBITMQ_VHOST', default=self.default_vhost),
                     help='RabbitMQ vhost to check ($RABBITMQ_VHOST, default: /)')
        self.add_opt('--no-tracing', action='store_true', default=False,
                     help='Check vhost does not have tracing enabled')

    def process_options(self):
        super(CheckRabbitMQVhost, self).process_options()
        self.vhost = self.get_opt('vhost')
        validate_chars(self.vhost, 'vhost', r'/\w\+-')
        self.no_tracing = self.get_opt('no_tracing')

    def parse_json(self, json_data):
        if not isList(json_data):
            raise UnknownError("non-list returned by RabbitMQ (got type '{0}'). {1}"\
                               .format(type(json_data), support_msg_api()))
        self.msg = "{0} vhost '{1}' ".format(self.name, self.vhost)
        vhost_item = self.check_vhost(json_data)
        if not vhost_item:
            return False
        tracing = vhost_item['tracing']
        if self.no_tracing and tracing:
            self.msg += ', tracing = {0}!'.format(tracing)
            self.warning()
        elif self.verbose:
            self.msg += ', tracing = {0}'.format(tracing)

    def check_vhost(self, json_data):
        for item in json_data:
            if item['name'] == self.vhost:
                self.msg += 'exists'
                return item
        self.msg += 'does not exist!'
        self.critical()
        return {}


if __name__ == '__main__':
    CheckRabbitMQVhost().main()
