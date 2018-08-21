#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-08-21 19:51:24 +0100 (Tue, 21 Aug 2018)
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

Nagios Plugin to check the time since the last OpenTSDB metric was ingested via the OpenTSDB API

This check ensures that OpenTSDB is still collecting metric data by checking that a default well known
metric has been collected in the last minute

You should choose a metric that is likely to change and not get deduplicated by collectors like TCollector

Tested on OpenTSDB 2.3 on HBase 1.4

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import time
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, isList, CriticalError, UnknownError, support_msg_api
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckOpenTSDBLatestMetricAge(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckOpenTSDBLatestMetricAge, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'OpenTSDB'
        self.default_port = 4242
        # requires metadata tracking to be enabled, not as universal across environments
        #self.path = '/api/query/last?timeseries='
        self.path = '/api/query?start=1m-ago&m=count:'
        self.auth = 'optional'
        self.json = True
        self.msg = 'OpenTSDB msg not defined yet'

    def add_options(self):
        super(CheckOpenTSDBLatestMetricAge, self).add_options()
        self.add_opt('-m', '--metric', default='proc.loadavg.1min',
                     help='Metric to query, should be a simple standard metric ' + \
                          '(default: \'proc.loadavg.1min\' from TCollector' + \
                          ', for Collectd specify \'load.load.shortterm\'' + \
                          ', for Telegraf specify \'telegraf.kernel_context_switches\')')
        self.add_thresholds(default_warning=30, default_critical=45)

    def process_options(self):
        super(CheckOpenTSDBLatestMetricAge, self).process_options()
        metric = self.get_opt('metric')
        self.path += '{}'.format(metric)
        self.validate_thresholds()

    # must be an object method for @override to work
    # pylint: disable=no-self-use
    # TODO: add better error handling to extract just message when metric doesn't exist
    def parse_json(self, json_data):
        if not isList(json_data):
            raise UnknownError('json data returned is not list as expected! {}'.format(support_msg_api()))
        if not json_data:
            raise CriticalError('OpenTSDB no metric received in last minute!')
        highest_timestamp = 0
        for metric in json_data:
            for timestamp in metric['dps'].keys():
                timestamp = int(timestamp)
                if timestamp > highest_timestamp:
                    highest_timestamp = timestamp
        log.info('highest timestamp = %s', highest_timestamp)
        metric_latest_age = time.time() - highest_timestamp
        if metric_latest_age < 0:
            raise UnknownError('OpenTSDB latest metric age is {} secs in the future! Mismatch server clocks?'\
                               .format(abs(metric_latest_age)))
        metric_latest_age = '{:.2f}'.format(metric_latest_age)
        self.msg = 'OpenTSDB latest metric age = {} secs'.format(metric_latest_age)
        self.check_thresholds(metric_latest_age)
        self.msg += ' | metric_latest_age={}s{}'.format(metric_latest_age, self.get_perf_thresholds())


if __name__ == '__main__':
    CheckOpenTSDBLatestMetricAge().main()
