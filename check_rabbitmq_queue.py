#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-25 17:39:31 +0000 (Sun, 25 Dec 2016)
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

Nagios Plugin to check a given RabbitMQ queue exists within a specified vhost via the RabbitMQ Management REST API

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


class CheckRabbitMQQueue(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckRabbitMQQueue, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'RabbitMQ'
        self.default_port = 15672
        self.default_user = 'guest'
        self.default_password = 'guest'
        self.default_vhost = '/'
        self.vhost = self.default_vhost
        self.queue = None
        self.expected_queue_state = 'running'
        self.expected_durable = None
        self.path = 'api/queues'
        self.json = True
        self.msg = 'msg not defined yet'
        self.check_response_code_orig = self.request.check_response_code
        self.request.check_response_code = self.check_response_code

    def add_options(self):
        super(CheckRabbitMQQueue, self).add_options()
        self.add_opt('-Q', '--queue', default=getenvs('RABBITMQ_QUEUE'),
                     help='RabbitMQ queue to check ($RABBITMQ_QUEUE)')
        self.add_opt('-O', '--vhost', default=getenvs('RABBITMQ_VHOST', default=self.default_vhost),
                     help='RabbitMQ vhost for queue ($RABBITMQ_VHOST, default: /)')
        self.add_opt('-U', '--durable',
                     help="Check queue durable (optional, arg must be: 'true' / 'false')")
        self.add_opt('-l', '--list-queues', action='store_true', help='List queues on given vhost and exit')

    def process_options(self):
        super(CheckRabbitMQQueue, self).process_options()
        self.vhost = self.get_opt('vhost')
        validate_chars(self.vhost, 'vhost', r'/\w\+-')
        self.path += '/' + urllib.quote_plus(self.vhost)
        self.queue = self.get_opt('queue')
        if self.get_opt('list_queues'):
            pass
        else:
            validate_chars(self.queue, 'queue', r'/\w\.\+-')
            self.path += '/' + urllib.quote_plus(self.queue)
        self.expected_durable = self.get_opt('durable')
        if self.expected_durable:
            self.expected_durable = self.expected_durable.lower()
            if self.expected_durable not in ('true', 'false'):
                self.usage("invalid --durable option '{0}' given, if specified must be either 'true' or 'false'".\
                           format(self.expected_durable))

    def check_response_code(self, req):
        if req.status_code != 200:
            if req.status_code == 404 and req.reason == 'Object Not Found':
                self.msg = "RabbitMQ queue '{0}' not found on vhost '{1}'!".format(self.queue, self.vhost)
                raise CriticalError(self.msg)
            else:
                self.check_response_code_orig(req)

    def parse_json(self, json_data):
        # when returning all queues, otherwise will return lone dict item or 404
        if self.get_opt('list_queues'):
            if not isList(json_data):
                raise UnknownError("non-list returned by RabbitMQ (got type '{0}'). {1}"\
                                   .format(type(json_data), support_msg_api()))
            print("RabbitMQ queues on vhost '{0}':\n".format(self.vhost))
            print('\n'.join([_['name'] for _ in json_data]))
            sys.exit(ERRORS['UNKNOWN'])
        self.msg = "RabbitMQ queue '{0}' ".format(self.queue)
        if self.verbose:
            self.msg += "on vhost '{0}' ".format(self.vhost)
        self.check_queue(json_data)

    def check_queue(self, json_data):
        if not isDict(json_data):
            raise UnknownError("non-dict passed to check_queue(), got type '{0}".format(type(json_data)))
        if json_data['name'] != self.queue:
            raise CriticalError("queue name returned '{0}' does not match expected queue '{1}'"\
                                .format(json_data['name'], self.queue))
        self.msg += 'exists'
        state = json_data['state']
        self.msg += ", state = '{0}'".format(state)
        if state != self.expected_queue_state:
            self.msg += " (expected '{0}')".format(self.expected_queue_state)
        queue_durable = str(json_data['durable']).lower()
        self.msg += ', durable = {0}'.format(queue_durable)
        if self.expected_durable and self.expected_durable != queue_durable:
            self.critical()
            self.msg += " (expected '{0}')".format(self.expected_durable)


if __name__ == '__main__':
    CheckRabbitMQQueue().main()
