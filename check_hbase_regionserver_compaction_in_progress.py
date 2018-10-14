#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-09-14 12:35:24 +0200 (Wed, 14 Sep 2016)
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

Nagios Plugin to check if an HBase major compaction is in progress on a given RegionServer via its JMX API

Raises Warning if any compaction is running - use this to check that no major compactions get triggered during the day
/ peak hours.

Set your enterprise monitoring alerting schedule to ignore warning status during off-peak scheduled
compaction time.

See also check_hbase_table_compaction_in_progress.py which checks for compactions on a table by table basis.

Tested on Hortonworks HDP 2.3 (HBase 1.1.2) and Apache HBase 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import logging
import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, jsonpp
    from harisekhon.utils import support_msg_api, isInt
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckHBaseCompactionInProgress(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseCompactionInProgress, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'HBase RegionServer'
        self.default_host = 'localhost'
        self.default_port = 16301
        self.path = '/jmx?qry=Hadoop:service=HBase,name=RegionServer,sub=Server'
        self.json = True
        self.auth = False
        self.msg = 'msg not defined'
        self.ok()

    def parse_json(self, json_data):
        compaction_queue_size = self.parse(json_data)
        self.msg = 'HBase RegionServer compaction '
        if compaction_queue_size > 0:
            self.warning()
            self.msg += 'in progress'
        else:
            self.msg += 'not in progress'
        self.msg += ', compactionQueueSize = {0}'.format(compaction_queue_size)
        self.msg += ' | compactionQueueSize={0};0;0'.format(compaction_queue_size)

    @staticmethod
    def parse(json_data):
        try:
            # it's already nicely layed out
            #if log.isEnabledFor(logging.DEBUG):
            #    log.debug('%s', jsonpp(json_data))
            compaction_queue_size = None
            for bean in json_data['beans']:
                if bean['name'] == 'Hadoop:service=HBase,name=RegionServer,sub=Server':
                    if log.isEnabledFor(logging.DEBUG):
                        log.debug('found RegionServer section:')
                        log.debug('%s', jsonpp(bean))
                    compaction_queue_size = bean['compactionQueueLength']
                    if not isInt(compaction_queue_size):
                        qquit('UNKNOWN', 'non-integer returned for compactionQueueLength! ' + support_msg_api())
                    return compaction_queue_size
        except KeyError as _:
            qquit('UNKNOWN', _ + ': failed to parse HBase Master jmx info. ' + support_msg_api())
        qquit('UNKNOWN', 'RegionServer mbean not found, double check this is pointing to an HBase RegionServer')


if __name__ == '__main__':
    CheckHBaseCompactionInProgress().main()
