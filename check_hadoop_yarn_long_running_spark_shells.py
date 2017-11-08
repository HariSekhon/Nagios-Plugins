#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: Tue Sep 26 09:24:25 CEST 2017
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

Nagios Plugin to Spark Shells that have been left running too long in Yarn via the Yarn Resource Manager REST API

This is to detect Spark Shells that have been left open holding Yarn cluster resources depriving other applications
of resources that the Spark Shell may not even be using

You can also use it to detect Spark Shells running on the wrong queue by using --exclude-queue and setting
--critical=1 to catch any Spark Shells running for any period of time on any other queue

Thresholds --warning / --critical apply to Spark Shell elapsed times in seconds and defaults to 10 hours for warning
(36000 secs), as you generally shouldn't be leaving your Spark Shell open for more than your working day and going
home as those are resources that could be used by overnight batch jobs

Detects both Spark Scala and PySpark Shells.

See also check_hadoop_yarn_long_running_apps.py which is a more flexible base program of this that can be applied
to any other Yarn application.

Tested on HDP 2.6.1 and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8

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
    from harisekhon.utils import plural
    from check_hadoop_yarn_long_running_apps import CheckHadoopYarnLongRunningApps
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.5.1'


class CheckHadoopYarnLongRunningSparkShells(CheckHadoopYarnLongRunningApps):

    def __init__(self):
        super(CheckHadoopYarnLongRunningSparkShells, self).__init__()
        self.msg = 'Spark Shells on Yarn breaching SLAs = '
        # set case insensitive in process_options() below
        # regex to catch 'Spark shell' (Scala) and 'PySparkShell'
        self.include = 'Spark.*Shell'
        self.queue = None
        self.limit = None
        self.list_apps = False

    def add_options(self):
        # shut up pylint this works
        super(CheckHadoopYarnLongRunningApps, self).add_options()  # pylint: disable=bad-super-call
        self.add_opt('-q', '--queue', help='Only checks Spark Shells on queues matching this given regex (optional)')
        self.add_opt('--exclude-queue',
                     help='Exclude Spark Shells running on queues matching this given regex (optional)')
        self.add_opt('-n', '--limit', default=1000, help='Limit number of results to search through (default: 1000)')
        self.add_opt('-l', '--list-apps', action='store_true', help='List yarn apps and exit')
        self.add_thresholds(default_warning=36000)

    def process_options(self):
        # shut up pylint this works
        super(CheckHadoopYarnLongRunningApps, self).process_options()  # pylint: disable=bad-super-call
        self.process_options_common()

    def parse_json(self, json_data):
        app_list = self.get_app_list(json_data)
        (num_shells_breaching_sla, num_matching_apps, max_elapsed, max_threshold_msg) = \
                                                                                self.check_app_elapsed_times(app_list)
        self.msg += '{0}, checked {1} Spark Shell{2} out of {3} running apps'\
                   .format(num_shells_breaching_sla, num_matching_apps, plural(num_matching_apps), len(app_list)) + \
                   ', longest running Spark Shell = {0} secs{1}'\
                   .format(max_elapsed, max_threshold_msg)
        self.msg += ' | num_spark_shells_breaching_SLA={0} max_elapsed_spark_shell_time={1}{2}'\
                    .format(num_shells_breaching_sla, max_elapsed, self.get_perf_thresholds())


if __name__ == '__main__':
    CheckHadoopYarnLongRunningSparkShells().main()
