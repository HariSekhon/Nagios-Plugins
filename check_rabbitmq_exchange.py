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

Nagios Plugin to check a given RabbitMQ exchange exists within a specified vhost via the RabbitMQ Management REST API

Requires the management plugin to be loaded.

Tested on RabbitMQ 3.4.4, 3.5.7, 3.6.6

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import traceback
import urllib
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import getenvs, isDict, isList, validate_chars, \
                                 CriticalError, UnknownError, ERRORS, support_msg_api
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckRabbitMQExchange(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckRabbitMQExchange, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'RabbitMQ'
        self.default_port = 15672
        self.default_user = 'guest'
        self.default_password = 'guest'
        self.default_vhost = '/'
        self.vhost = self.default_vhost
        self.exchange = None
        self.expected_type = None
        self.valid_exchange_types = ('direct', 'fanout', 'headers', 'topic')
        self.expected_durable = None
        self.path = 'api/exchanges'
        self.json = True
        self.msg = 'msg not defined yet'
        self.check_response_code_orig = self.request.check_response_code
        self.request.check_response_code = self.check_response_code

    def add_options(self):
        super(CheckRabbitMQExchange, self).add_options()
        self.add_opt('-E', '--exchange', default=getenvs('RABBITMQ_EXCHANGE'),
                     help='RabbitMQ exchange to check ($RABBITMQ_EXCHANGE)')
        self.add_opt('-O', '--vhost', default=getenvs('RABBITMQ_VHOST', default=self.default_vhost),
                     help='RabbitMQ vhost for exchange ($RABBITMQ_VHOST, default: /)')
        self.add_opt('-T', '--type', help='Check exchange is of given type (optional, must be one of: {0})'\
                                          .format(', '.join(self.valid_exchange_types)))
        self.add_opt('-U', '--durable', help="Check exchange durable (optional, arg must be: 'true' / 'false')")
        self.add_opt('-l', '--list-exchanges', action='store_true', help='List exchanges on given vhost and exit')

    def process_options(self):
        super(CheckRabbitMQExchange, self).process_options()
        self.vhost = self.get_opt('vhost')
        validate_chars(self.vhost, 'vhost', r'/\w\+-')
        self.path += '/' + urllib.quote_plus(self.vhost)
        self.exchange = self.get_opt('exchange')
        if self.get_opt('list_exchanges'):
            pass
        else:
            if self.exchange == '':
                # nameless exchange
                pass
            else:
                validate_chars(self.exchange, 'exchange', r'/\w\.\+-')
            self.path += '/' + urllib.quote_plus(self.exchange)
        self.expected_type = self.get_opt('type')
        self.expected_durable = self.get_opt('durable')
        if self.expected_type and self.expected_type not in self.valid_exchange_types:
            self.usage("invalid --type '{0}' given, if specified must be one of: {1}"\
                       .format(self.expected_type, ', '.join(self.valid_exchange_types)))
        if self.expected_durable:
            self.expected_durable = self.expected_durable.lower()
            if self.expected_durable not in ('true', 'false'):
                self.usage("invalid --durable '{0}' given, if specified must be either 'true' or 'false'".\
                           format(self.expected_durable))

    def check_response_code(self, req):
        if req.status_code != 200:
            if req.status_code == 404 and req.reason == 'Object Not Found':
                self.msg = "RabbitMQ vhost '{0}' not found!".format(self.vhost)
                raise CriticalError(self.msg)
            else:
                self.check_response_code_orig(req)

    def parse_json(self, json_data):
        # when returning all vhosts, otherwise will return lone dict item or 404
        if self.get_opt('list_exchanges'):
            if not isList(json_data):
                raise UnknownError("non-list returned by RabbitMQ (got type '{0}'). {1}"\
                                   .format(type(json_data), support_msg_api()))
            print("RabbitMQ Exchanges on vhost '{0}':\n".format(self.vhost))
            exchanges = [_['name'] for _ in json_data]
            for key, item in enumerate(exchanges):
                if item == '':
                    exchanges[key] = '<nameless>'
            print('\n'.join([_['name'] for _ in json_data if _['name']]))
            sys.exit(ERRORS['UNKNOWN'])
        self.msg = "RabbitMQ exchange '{0}' ".format(self.exchange)
        if self.verbose:
            self.msg += "on vhost '{0}' ".format(self.vhost)
        self.check_exchange(json_data)

    def check_exchange(self, json_data):
        if not isDict(json_data):
            raise UnknownError("non-dict passed to check_exchange), got type '{0}".format(type(json_data)))
        if json_data['name'] != self.exchange:
            raise CriticalError("exchange name returned '{0}' does not match expected exchange '{1}'"\
                                .format(json_data['name'], self.exchange))
        self.msg += 'exists'
        exchange_type = str(json_data['type']).lower()
        self.msg += ', type = {0}'.format(exchange_type)
        if self.expected_type and self.expected_type != exchange_type:
            self.critical()
            self.msg += " (expected '{0}')".format(self.expected_type)
        exchange_durable = str(json_data['durable']).lower()
        self.msg += ', durable = {0}'.format(exchange_durable)
        if self.expected_durable and self.expected_durable != exchange_durable:
            self.critical()
            self.msg += " (expected '{0}')".format(self.expected_durable)


if __name__ == '__main__':
    CheckRabbitMQExchange().main()
