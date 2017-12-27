#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-11-26 18:55:00 +0100 (Sun, 26 Nov 2017)
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

Nagios Plugin to check Logstash hot threads via the Logstash Rest API

Optional thresholds apply to the % CPU time for the busiest hot thread by default, or if using the
--top-3 switch then the total sum of % CPU time for top 3 hot threads combined

The top hot thread CPU % and state is output regardless, and perfdata for the top hot thread CPU % and
the top 3 hot threads total CPU % is output for graphing

API is only available in Logstash 5.x onwards, will get connection refused on older versions

Ensure Logstash options:
  --http.host should be set to 0.0.0.0 if querying remotely
  --http.port should be set to the same port that you are querying via this plugin's --port switch

Tested on Logstash 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1

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
    #from harisekhon.utils import log
    from harisekhon.utils import UnknownError, support_msg_api
    from harisekhon.utils import isDict, isList
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckLogstashHotThreads(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckLogstashHotThreads, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Logstash'
        self.default_port = 9600
        # could add pipeline name to end of this endpoint but error would be less good 404 Not Found
        # Logstash 5.x /_node/pipeline <= use -5 switch for older Logstash
        # Logstash 6.x /_node/pipelines
        self.path = '/_node/hot_threads'
        self.auth = False
        self.json = True
        self.msg = 'Logstash hot threads msg not defined yet'
        self.plugins = None

    def add_options(self):
        super(CheckLogstashHotThreads, self).add_options()
        self.add_opt('--top-3', action='store_true',
                     help='Test the total sum cpu percentage of the top 3 hot threads' + \
                          ' instead of the top thread')
        self.add_thresholds(default_warning=50)

    def process_options(self):
        super(CheckLogstashHotThreads, self).process_options()
        self.validate_thresholds(percent=True, optional=True)

    def parse_json(self, json_data):
        if not isDict(json_data):
            raise UnknownError('non-dict returned for hot threads. {}'.format(support_msg_api()))
        hot_threads = json_data['hot_threads']['threads']
        top_3 = self.get_opt('top_3')
        sum_percent = 0
        last_percent = None
        for thread in hot_threads:
            thread_percent = thread['percent_of_cpu_time']
            if last_percent is None:
                last_percent = thread_percent
            if thread_percent > last_percent:
                raise UnknownError('assertion failure - subsequent thread percent is unexpectedly higher' + \
                                   ', out of expected order. {}'.format(support_msg_api()))
            sum_percent += thread_percent
        self.msg = 'Logstash '
        if top_3:
            self.msg += 'top 3 hot threads cpu percentage = {}%'.format(sum_percent)
            self.check_thresholds(sum_percent)
            self.msg += ', '
        # they come sorted with highest at top
        top_thread = hot_threads[0]
        name = top_thread['name']
        percent = top_thread['percent_of_cpu_time']
        state = top_thread['state']
        # not available in 5.0, only later versions such as 6.0
        #thread_id = top_thread['thread_id']
        self.msg += 'top hot thread \'{}\' cpu percentage = {}%'.format(name, percent)
        if not top_3:
            self.check_thresholds(percent)
        self.msg += ', state = \'{}\''.format(state)
        #self.msg += ', id = {}'.format(state, thread_id)
        if self.verbose:
            if not isList(top_thread['traces']):
                raise UnknownError('hot thread\'s trace field is not a list. {}'.format(support_msg_api()))
            traces = '\\n'.join(top_thread['traces'])
            self.msg += ', traces: {}'.format(traces)
        if not top_3:
            self.msg += ', top 3 hot threads cpu percentage = {}%'.format(sum_percent)
        self.msg += ' | top_hot_thread_cpu_percentage={}%'.format(percent)
        if not top_3:
            self.msg += '{}'.format(self.get_perf_thresholds())
        self.msg += ' top_three_hot_thread_cpu_percentage={}%'.format(sum_percent)
        if top_3:
            self.msg += '{}'.format(self.get_perf_thresholds())


if __name__ == '__main__':
    CheckLogstashHotThreads().main()
