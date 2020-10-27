#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-02-15 23:58:38 +0000 (Mon, 15 Feb 2016)
#  port of Perl version Date: 2015-01-04 20:49:58 +0000 (Sun, 04 Jan 2015)
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

Nagios Plugin to check a Kafka cluster is working by using the APIs to validate passing a unique message
through the brokers

Thresholds apply to max produce / consume message timings which are also output as perfdata for graphing.
Total time includes setup, connection and message timings etc.

If partition is not specified it'll randomize the partition selection, but this could result in state flapping
in between different runs that may select a malfunctioning partition one time and working one the other time
so ideally you should specify the --partition explicitly and implement a separate check per partition.

See also Perl version check_kafka.pl of which this is a port of since one of the underlying Perl library's
dependencies developed an autoload bug (now auto-patched in the automated build of this project).

The Perl version does have better info for --list-partitions however, including Replicas,
ISRs and Leader info per partition as the Perl API exposes this additional information.

Tested on Kafka 0.8.1, 0.8.2.2, 0.9.0.1
"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import random
import sys
import traceback
try:
    from kafka import KafkaConsumer, KafkaProducer
    from kafka.common import KafkaError, TopicPartition
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, log_option, ERRORS, CriticalError, UnknownError
    from harisekhon.utils import validate_hostport, validate_int, get_topfile, random_alnum, validate_chars, isSet
    from harisekhon import PubSubNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.5.5'


class CheckKafka(PubSubNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckKafka, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Kafka'
        self.default_host = 'localhost'
        self.default_port = '9092'
        self.producer = None
        self.consumer = None
        self.topic = None
        self.client_id = 'Hari Sekhon {prog} {version}'.format(prog=os.path.basename(get_topfile()),
                                                               version=__version__)
        self.group_id = '{client_id} {pid} {random}'.format(client_id=self.client_id,
                                                            pid=os.getpid(),
                                                            random=random_alnum(10))
        self.acks = '1'
        self.retries = 0
        self.partition = None
        self.topic_partition = None
        self.brokers = None
        self.timeout_ms = None
        self.start_offset = None
        self.sleep_secs = 0
        self.sleep_usage = 'Sleep in seconds between producing and consuming from given topic' + \
                           ' (optional, default: {} secs)'.format(self.default_sleep_secs)

    def add_options(self):
        # super(CheckKafka, self).add_options()
        self.add_opt('-B', '--brokers',
                     dest='brokers', metavar='broker_list',
                     help='Kafka Broker seed list in form host[:port],host2[:port2]... ' + \
                             '($KAFKA_BROKERS, $KAFKA_HOST:$KAFKA:PORT, default: localhost:9092)')
        self.add_opt('-H', '--host',
                     help='Kafka broker host, used to construct --brokers if not specified ' + \
                          '($KAFKA_HOST, default: {0})'.format(self.default_host))
        self.add_opt('-P', '--port',
                     help='Kafka broker port, used to construct --brokers if not specified ' + \
                          '($KAFKA_PORT, default: {0})'.format(self.default_port))
        self.add_opt('-T', '--topic', default=os.getenv('KAFKA_TOPIC'), help='Kafka Topic ($KAFKA_TOPIC)')
        self.add_opt('-p', '--partition', type=int, help='Kafka Partition (default: random)')
        self.add_opt('-a', '--acks', default=1, choices=['1', 'all'],
                     help='Acks to require from Kafka. Valid options are \'1\' for Kafka ' +
                     'partition leader, or \'all\' for all In-Sync Replicas (may block causing ' +
                     'timeout if replicas aren\'t available, default: 1)')
        self.add_opt('-s', '--sleep', type=float, default=1.0, metavar='secs', help=self.sleep_usage)
        self.add_opt('--list-topics', action='store_true', help='List Kafka topics from broker(s) and exit')
        self.add_opt('--list-partitions', action='store_true',
                     help='List Kafka topic paritions from broker(s) and exit')
        self.add_thresholds(default_warning=1, default_critical=2)

    def process_broker_args(self):
        self.brokers = self.get_opt('brokers')
        host = self.get_opt('host')
        port = self.get_opt('port')
        host_env = os.getenv('KAFKA_HOST')
        port_env = os.getenv('KAFKA_PORT')
        if not host:
            # protect against blank strings in env vars
            if host_env:
                host = host_env
            else:
                host = self.default_host
        if not port:
            # protect against blank strings in env vars
            if port_env:
                port = port_env
            else:
                port = self.default_port
        brokers_env = os.getenv('KAFKA_BROKERS')
        if not self.brokers:
            if brokers_env:
                self.brokers = brokers_env
            else:
                self.brokers = '{0}:{1}'.format(host, port)
        brokers = ''
        for broker in self.brokers.split(','):
            if ':' not in broker:
                broker += ':{0}'.format(port)
            validate_hostport(broker)
            brokers += '{0}, '.format(broker)
        brokers = brokers.rstrip(', ')
        self.brokers = brokers
        log_option('brokers', self.brokers)

    def process_args(self):
        self.process_broker_args()
        self.timeout_ms = max((self.timeout * 1000 - 1000) / 2, 1000)
        sleep_secs = self.get_opt('sleep')
        if sleep_secs:
            # validation done through property wrapper
            self.sleep_secs = sleep_secs
            log_option('sleep', sleep_secs)
        try:
            list_topics = self.get_opt('list_topics')
            list_partitions = self.get_opt('list_partitions')
            if list_topics:
                self.print_topics()
                sys.exit(ERRORS['UNKNOWN'])
        except KafkaError:
            raise CriticalError(self.exception_msg())

        self.topic = self.get_opt('topic')
        if self.topic:
            validate_chars(self.topic, 'topic', r'\w\.-')
        elif list_topics or list_partitions:
            pass
        else:
            self.usage('--topic not specified')

        # because this could fail to retrieve partition metadata and we want it to throw CRITICAL if so
        try:
            self.process_partitions(list_partitions)
        except KafkaError:
            err = self.exception_msg()
            raise CriticalError(err)

        self.topic_partition = TopicPartition(self.topic, self.partition)
        self.acks = self.get_opt('acks')
        if self.acks == 'all':
            log_option('acks', self.acks)
        else:
            validate_int(self.acks, 'acks')
            self.acks = int(self.acks)
        self.validate_thresholds()

    def process_partitions(self, list_partitions=False):
        if list_partitions:
            if self.topic:
                self.print_topic_partitions(self.topic)
            else:
                for topic in self.get_topics():
                    self.print_topic_partitions(topic)
            sys.exit(ERRORS['UNKNOWN'])
        self.partition = self.get_opt('partition')
        # technically optional, will hash to a random partition, but need to know which partition to get offset
        if self.partition is None:
            log.info('partition not specified, getting random partition')
            self.partition = random.choice(list(self.get_topic_partitions(self.topic)))
            log.info('selected partition %s', self.partition)
        validate_int(self.partition, "partition", 0, 10000)

    def run(self):
        try:
            super(CheckKafka, self).run()
        #except KafkaError as _:
            #raise CriticalError(_)
        except KafkaError:
            err = self.exception_msg()
            raise CriticalError(err)

    def exception_msg(self):
        err = traceback.format_exc().split('\n')[-2]
        if 'NoBrokersAvailable' in err:
            err += ". Could not connect to Kafka broker(s) '{0}'".format(self.brokers)
        return err

    def get_topics(self):
        self.consumer = KafkaConsumer(
            bootstrap_servers=self.brokers,
            client_id=self.client_id,
            #request_timeout_ms=self.timeout_ms + 1, # must be larger than session timeout
            #session_timeout_ms=self.timeout_ms,
            )
        return self.consumer.topics()

    def print_topics(self):
        print('Kafka Topics:\n')
        for topic in self.get_topics():
            print(topic)

    def get_topic_partitions(self, topic):
        self.consumer = KafkaConsumer(
            topic,
            bootstrap_servers=self.brokers,
            client_id=self.client_id,
            #request_timeout_ms=self.timeout_ms
            )
        if topic not in self.get_topics():
            raise CriticalError("topic '{0}' does not exist on Kafka broker".format(topic))
        partitions = self.consumer.partitions_for_topic(topic)
        if not isSet(partitions):
            raise UnknownError('partitions returned type is {}, not a set as expected'.format(type(partitions)))
        return partitions

    def print_topic_partitions(self, topic):
        print('Kafka topic \'{0}\' partitions:\n'.format(topic))
        #for partition in self.get_topic_partitions(topic):
        #    print(partition)
        print(list(self.get_topic_partitions(topic)))
        print()

    def subscribe(self):
        self.consumer = KafkaConsumer(
            #self.topic,
            bootstrap_servers=self.brokers,
            # client_id=self.client_id,
            # group_id=self.group_id,
            #request_timeout_ms=self.timeout_ms
            )
            #key_serializer
            #value_serializer
        # this is only a guess as Kafka doesn't expose it's API version
        #log.debug('kafka api version: %s', self.consumer.config['api_version'])
        log.debug('partition assignments: {0}'.format(self.consumer.assignment()))

        # log.debug('subscribing to topic \'{0}\' parition \'{1}\''.format(self.topic, self.partition))
        # self.consumer.subscribe(TopicPartition(self.topic, self.partition))
        # log.debug('partition assignments: {0}'.format(self.consumer.assignment()))

        log.debug('assigning partition {0} to consumer'.format(self.partition))
        # self.consumer.assign([self.partition])
        self.consumer.assign([self.topic_partition])
        log.debug('partition assignments: {0}'.format(self.consumer.assignment()))

        log.debug('getting current offset')
        # see also highwater, committed, seek_to_end
        self.start_offset = self.consumer.position(self.topic_partition)
        if self.start_offset is None:
            # don't do this, I've seen scenario where None is returned and all messages are read again, better to fail
            # log.warn('consumer position returned None, resetting to zero')
            # self.start_offset = 0
            raise UnknownError('Kafka Consumer reported current starting offset = {0}'.format(self.start_offset))
        log.debug('recorded starting offset \'{0}\''.format(self.start_offset))
        # self.consumer.pause()

    def publish(self):
        log.debug('creating producer')
        self.producer = KafkaProducer(
            bootstrap_servers=self.brokers,
            client_id=self.client_id,
            acks=self.acks,
            batch_size=0,
            max_block_ms=self.timeout_ms,
            #request_timeout_ms=self.timeout_ms + 1, # must be larger than session timeout
            #session_timeout_ms=self.timeout_ms,
            )
            #key_serializer
            #value_serializer
        log.debug('producer.send()')
        self.producer.send(
            self.topic,
            key=self.key.encode('utf-8'),
            partition=self.partition,
            value=self.publish_message.encode('utf-8')
            )
        log.debug('producer.flush()')
        self.producer.flush()

    def consume(self):
        self.consumer.assign([self.topic_partition])
        log.debug('consumer.seek({0})'.format(self.start_offset))
        self.consumer.seek(self.topic_partition, self.start_offset)
        # self.consumer.resume()
        log.debug('consumer.poll(timeout_ms={0})'.format(self.timeout_ms))
        obj = self.consumer.poll(timeout_ms=self.timeout_ms)
        log.debug('msg object returned: %s', obj)
        msg = None
        try:
            for consumer_record in obj[self.topic_partition]:
                if consumer_record.key == self.key.encode('utf-8'):
                    msg = consumer_record.value.decode('utf-8')
                    break
        except KeyError:
            raise UnknownError('TopicPartition key was not found in response')
        if msg is None:
            raise UnknownError("failed to find matching consumer record with key '{0}'".format(self.key))
        return msg


if __name__ == '__main__':
    CheckKafka().main()
