#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-15 21:01:39 +0000 (Thu, 15 Dec 2016)
#  originally started in Perl
#  Date: 2014-05-03 20:42:47 +0100 (Sat, 03 May 2014)
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

Nagios Plugin to check a RabbitMQ broker via the AMQP API by passing a unique message through the broker,
reading it back and validating the content

Thresholds apply to max publish / consume message timings which are also output as perfdata for graphing.
Total time includes setup, connection and message timings etc.

Makes thorough use of the API checks at every stage through the code to be as robust as possible to detecting issues.

Important Usage Notes:

1. If a Queue + Exchange are both specified, then both will be (re)created and the queue will be bound to the exchange.
2. Queues and Exchange creation will fail if they already exist and have different conflicting parameters
3. Queue + Exchange options should be used by advanced users only - depending on your deployment you could end up
   building up surplus messages in the queue, occupying increasing amounts of RAM. You must also take account of your
   routing topology as message consumption characteristics to avoid losing messages on pre-existing queues.
4. Beginners should omit --queue and --exchange options and just use the temporary auto-generated queue on the nameless
   exchange to avoid building up messages in RAM.

Tested on RabbitMQ 3.4.4, 3.5.7, 3.6.6

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import socket
import sys
import traceback
try:
    import pika
    import pika.exceptions
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, log_option, CriticalError, UnknownError, getenvs
    from harisekhon.utils import validate_host, validate_port, validate_user, validate_password, \
                                 validate_int, validate_chars
    from harisekhon import PubSubNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.5.2'


class CheckRabbitMQ(PubSubNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckRabbitMQ, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'RabbitMQ'
        self.default_host = 'localhost'
        self.default_port = 5672
        self.default_user = 'guest'
        self.default_password = 'guest'
        self.default_vhost = '/'
        # nameless exchange
        self.default_exchange = ''
        # will default to direct
        self.default_exchange_type = 'direct'
        self.default_queue = None
        self.default_no_ack = True
        self.default_durable = True
        self.default_conn_attempts = 1
        self.default_retry_delay = 0
        self.ssl = False

        self.host = self.default_host
        self.port = self.default_port
        self.user = None
        self.password = None
        self.vhost = self.default_vhost
        self.channel = None
        self.exchange = self.default_exchange
        self.exchange_type = self.default_exchange_type
        self.valid_exchange_types = ('direct', 'headers', 'fanout', 'topic')
        self.queue = self.default_queue
        self.routing_key = None

        self.conn = None
        self.no_ack = self.default_no_ack
        self.durable = True
        self.confirmed = False
        self.use_transactions = False
        self.connection_attempts = self.default_conn_attempts
        self.retry_delay = self.default_retry_delay
        self.consumed_message = None
        self.message_count = 0
        self.message_limit = 10000
        self.sleep_secs = 0
        self.consumer_tag = '{prog} {version} host {host} pid {pid}'\
                            .format(prog=self._prog,
                                    version=__version__,
                                    host=socket.gethostname(),
                                    pid=os.getpid())
        self.msg = 'msg not defined yet'
        self.sleep_usage = 'Sleep in seconds between producing and consuming from given exchange ' + \
                           ' (optional, default: {} secs)'.format(self.default_sleep_secs)

    def add_options(self):
        self.add_hostoption(default_host=self.default_host, default_port=self.default_port)
        self.add_useroption(default_user=self.default_user, default_password=self.default_password)
        self.add_opt('-S', '--use-ssl', action='store_true', help='Use SSL connection')
        self.add_opt('-O', '--vhost', default=getenvs('RABBITMQ_VHOST', default=self.default_vhost),
                     help='{name} Vhost to connect to ($RABBITMQ_VHOST, default: {default_vhost})'\
                          .format(name=self.name, default_vhost=self.default_vhost))
        self.add_opt('-E', '--exchange', default=getenvs('RABBITMQ_EXCHANGE', default=self.default_exchange),
                     help='Exchange to use ($RABBITMQ_EXCHANGE, default: {default_exchange}, '\
                          .format(default_exchange=self.default_exchange) + "blank uses the nameless exchange)")
        self.add_opt('-T', '--exchange-type', default=getenvs('RABBITMQ_EXCHANGE_TYPE',
                                                              default=self.default_exchange_type),
                     help='Exchange type to use ($RABBITMQ_EXCHANGE_TYPE, default: {default_exchange_type})'\
                          .format(default_exchange_type=self.default_exchange_type))
        self.add_opt('-Q', '--queue', default=getenvs('RABBITMQ_QUEUE', default=self.default_queue),
                     help='Queue to create and bind to exchange ($RABBITMQ_QUEUE, ' + \
                          'default: {default_queue}, auto-generated if not supplied)'.\
                          format(default_queue=self.default_queue))
        self.add_opt('-R', '--routing-key', default=getenvs('RABBITMQ_ROUTING_KEY', default=None),
                     help='Routing Key to use when publishing unique test message ' + \
                          'to exchange ($RABBITMQ_ROUTING_KEY, defaults to same as queue name if not supplied)')
        #self.add_opt('-N', '--no-ack', action='store_true', default=self.default_no_ack,
        #             help='Do not use acknowledgements')
        self.add_opt('--non-durable', action='store_true',
                     help='Publish message as non-persistent / create queue as non-durable')
        self.add_opt('--use-transactions', action='store_true',
                     help='Use AMQP transactions instead of RabbitMQ confirmation (transactions are ~250x slower')
        self.add_opt('-C', '--connection-attempts', default=self.default_conn_attempts,
                     help='Number of connection attempts (default: {default_conn_attempts})'\
                          .format(default_conn_attempts=self.default_conn_attempts))
        self.add_opt('-r', '--retry-delay', default=self.default_retry_delay,
                     help='Retry delay between connection attempts (default: {default_retry_delay})')
        self.add_opt('-s', '--sleep', type=float, default=1.0, metavar='secs', help=self.sleep_usage)
        self.add_thresholds(default_warning=1, default_critical=2)

    def run(self):
        try:
            super(CheckRabbitMQ, self).run()
        except (pika.exceptions.AMQPError, pika.exceptions.ChannelError, pika.exceptions.RecursionError):
            err = self.exception_msg()
            raise CriticalError(err)

    def process_args(self):
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        self.user = self.get_opt('user')
        self.password = self.get_opt('password')
        validate_host(self.host)
        validate_port(self.port)
        self.port = int(self.port)
        validate_user(self.user)
        validate_password(self.password)
        self.vhost = self.get_opt('vhost')
        self.vhost = self.vhost if self.vhost else '/'
        validate_chars(self.vhost, 'vhost', r'/\w\._-')
        self.exchange = self.get_opt('exchange')
        if self.exchange:
            validate_chars(self.exchange, 'exchange', r'\w\._-')
        else:
            log_option('exchange', self.exchange)
        self.exchange_type = self.get_opt('exchange_type')
        if self.exchange_type:
            if self.exchange_type not in self.valid_exchange_types:
                self.usage('invalid --exchange-type given, expected one of: {valid_exchange_types}'\
                           .format(valid_exchange_types=', '.join(self.valid_exchange_types)))
        log_option('exchange type', self.exchange_type)
        self.queue = self.get_opt('queue')
        if self.queue:
            validate_chars(self.queue, 'queue', r'\w\._-')
        else:
            log_option('queue', self.queue)
        self.routing_key = self.get_opt('routing_key')
        if not self.routing_key:
            self.routing_key = self.queue
        log_option('routing key', self.routing_key)
        #self.no_ack = self.get_opt('no_ack')
        log_option('no ack', self.no_ack)
        self.connection_attempts = self.get_opt('connection_attempts')
        validate_int(self.connection_attempts, 'connection attempts', min_value=1, max_value=10)
        self.connection_attempts = int(self.connection_attempts)
        self.retry_delay = self.get_opt('retry_delay')
        validate_int(self.retry_delay, 'retry delay', min_value=0, max_value=10)
        self.retry_delay = int(self.retry_delay)
        self.use_transactions = self.get_opt('use_transactions')
        #self.durable = not self.get_opt('non_durable')
        if self.get_opt('non_durable'):
            self.durable = False
        log_option('non-durable', not self.durable)
        sleep_secs = self.get_opt('sleep')
        if sleep_secs:
            # validation done through property wrapper
            self.sleep_secs = sleep_secs
        log_option('sleep secs', self.sleep_secs)
        self.validate_thresholds()

    def check_connection(self):
        log.debug('checking connection is still open')
        if not self.conn.is_open:
            raise CriticalError('connection closed')

    def check_channel(self):
        log.debug('checking channel is still open')
        if not self.channel.is_open:
            raise CriticalError('channel closed')

    @staticmethod
    def connection_blocked_callback(method):
        # could really be a warning
        raise CriticalError('connection blocked: {0}'.format(method.reason) + \
                            '(is the RabbitMQ broker low on resources eg. RAM / disk?)')

    def connection_timeout_handler(self):
        raise CriticalError("connection timed out while communicating with {name} broker '{host}:{port}'"\
                            .format(name=self.name, host=self.host, port=self.port))

    def connection_cancel_callback(self):
        raise CriticalError('{name} broker {host}:{port} sent channel cancel notification'\
                            .format(name=self.name, host=self.host, port=self.port))

#    @staticmethod
#    def connection_on_return_callback(channel, method, properties, body):  # pylint: disable=unused-argument
#        raise CriticalError('return callback by broker')

    def confirm_delivery_callback(self, method):
        self.confirmed = True

#    @staticmethod
#    def on_flow_callback():
#        raise WarningError('broker sent channel flow control backpressure (broker may be struggling with load)')

    def subscribe(self):
        credentials = pika.credentials.PlainCredentials(self.user, self.password)
        parameters = pika.ConnectionParameters(host=self.host,
                                               port=self.port,
                                               virtual_host=self.vhost,
                                               credentials=credentials,
                                               heartbeat_interval=1,
                                               ssl=self.ssl,
                                               connection_attempts=self.default_conn_attempts,
                                               retry_delay=self.retry_delay,
                                               backpressure_detection=True,
                                               # socket_timeout – Use for high latency networks
                                              )
        self.conn = pika.BlockingConnection(parameters=parameters)
        log.debug('adding blocked connection callback')
        self.conn.add_on_connection_blocked_callback(self.connection_blocked_callback)
        log.debug('adding connection timeout to one 3rd of total timeout (%.2f out of %.2f secs)',
                  self.timeout / 3, self.timeout)
        # no args to this callback
        self.conn.add_timeout(max(self.timeout - 1, 1), self.connection_timeout_handler)
        #
        self.check_connection()
        log.info('requesting channel')
        self.channel = self.conn.channel()
        log.info('got channel number %s', self.channel.channel_number)
        log.debug('adding channel cancel callback')
        self.channel.add_on_cancel_callback(self.connection_cancel_callback)
        # newer versions of RabbitMQ won't use this but will instead use TCP backpressure
        # not available on BlockingChannel
        #self.channel.add_on_flow_callback(self.on_flow_callback)
        log.debug('adding return callback')
        # not available on BlockingChannel
        #self.channel.add_on_return_callback(self.connection_return_callback)
        if self.use_transactions:
            log.info('setting channel to use AMQP transactions')
            self.channel.tx_select()
        else:
            log.info('setting RabbitMQ specific channel confirmation')
            # different in BlockingChannel
            #self.channel.confirm_delivery(callback=self.confirm_delivery_callback, nowait=False)
            self.channel.confirm_delivery()
        self.check_channel()
        log.info('declaring queue \'%s\'', self.queue)
        if self.queue:
            result = self.channel.queue_declare(queue=self.queue, durable=self.durable)
            if self.queue != result.method.queue:
                raise UnknownError("queue returned in subscribe ('{queue_returned}') "\
                                   .format(queue_returned=result.method.queue) + \
                                   "did not match requested queue name ('{queue}')"\
                                   .format(queue=self.queue))
        else:
            # auto-generate uniq queue, durable flag is ignored for exclusive
            result = self.channel.queue_declare(exclusive=True)
            self.queue = result.method.queue
            if not self.routing_key:
                self.routing_key = self.queue
        log.info('was assigned unique exclusive queue: %s', self.queue)
        if self.exchange:
            log.info("declaring exchange: '%s', type: '%s'", self.exchange, self.exchange_type)
            self.channel.exchange_declare(exchange=self.exchange,
                                          exchange_type=self.exchange_type)
            # if using nameless exchange this isn't necessary as routing key will send to queue
            log.info("binding queue '%s' to exchange '%s'", self.queue, self.exchange)
            self.channel.queue_bind(exchange=self.exchange,
                                    queue=self.queue)

    def publish(self):
        self.check_connection()
        self.check_channel()
        if self.durable:
            log.info('setting message to durable')
            properties = pika.BasicProperties(delivery_mode=2)
        else:
            log.info('setting message as non-durable')
            properties = pika.BasicProperties()
        #result = self.channel.basic_publish(exchange=self.exchange,
        # gives more error information via exceptions UnroutableError / NackError
        # returns None so don't collect as result
        log.info("publishing message to exchange '{exchange}' using routing key '{routing_key}'"\
                 .format(exchange=self.exchange, routing_key=self.routing_key))
        self.channel.publish(exchange=self.exchange,
                             routing_key=self.routing_key,
                             body=self.publish_message,
                             properties=properties,
                             mandatory=True,
                             # RabbitMQ does not support 'immediate', use TTL zero on queue instead
                             # CRITICAL: ConnectionClosed: (540, 'NOT_IMPLEMENTED - immediate=true')
                             #immediate=True
                            )
        # too basic, only returned via basic_publish
        #if not result:
        #    raise CriticalError('message publish failed!')
        if self.use_transactions:
            log.info('committing transaction')
            self.channel.tx_commit()

    def consumer_callback(self, channel, method, properties, body):
        log.info('callback received message "%s"', body)
        # don't ack as messages could stay in queue indefinitely
        #delivery_tag = method.delivery_tag
        #log.info('ack\'ing message with delivery tag \'%s\'', delivery_tag)
        #channel.basic_ack(delivery_tag = delivery_tag)
        message = body
        # should be the only message on our private channel
        if message == self.publish_message:
            log.info('consumed matching message, stopping consumer')
            self.consumed_message = message
            channel.stop_consuming(consumer_tag=self.consumer_tag)
            # 'bad things will happen' if passing the wrong consumer_tag
            #channel.basic_cancel(self.consumer_tag)
        else:
            #raise CriticalError('wrong message returned by broker, does not match unique message sent!')
            self.message_count += 1
            if self.message_count > self.message_limit:
                raise CriticalError('expected message not received within {message_limit} message limit'\
                                    .format(message_limit=self.message_limit))

    def consume(self):
        self.check_connection()
        self.check_channel()
        def connection_timeout_handler():
            raise CriticalError("unique message not returned on queue '{queue}' within {secs:.2f} secs"\
                                .format(queue=self.queue, secs=self.timeout / 3) + \
                                ", consumer timed out while consuming messages from {name} broker '{host}:{port}'"\
                                .format(name=self.name, host=self.host, port=self.port))
        self.conn.add_timeout(self.timeout / 3, connection_timeout_handler)
        # don't re-declare, queue should still exist otherwise error out
        #channel.queue_declare(queue = 'hello')
        # don't ack as messages could stay in queue indefinitely
        self.consumer_tag = self.channel.basic_consume(self.consumer_callback,
                                                       queue=self.queue,
                                                       # let broker autogenerate consumer_tag
                                                       # consumer_tag = self.consumer_tag),
                                                       no_ack=self.no_ack
                                                      )
        # could also use non-callback mechanism - generator that yields tuples (method, properties, body)
        # requires self.channel.cancel() from within loop
        # self.channel.consume(self.queue,
        #                      no_ack = True,
        #                      exclusive = True,
        #                      arguments = None,
        #                      inactivity_timeout = self.timeout/3)
        log.debug('start consuming')
        self.channel.start_consuming()
        # could instead use basic_get to return single message
        # self.channel.basic_get(queue = self.queue, no_ack = True)
        log.info('closing connection to broker')
        self.conn.close(reply_code=200, reply_text='Normal shutdown')
        return self.consumed_message


if __name__ == '__main__':
    CheckRabbitMQ().main()
