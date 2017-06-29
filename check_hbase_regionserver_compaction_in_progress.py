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

Nagios Plugin to check if an HBase major compaction is in progress on a given RegionServer via the RegionServer's JMX

Raises Warning if any compaction is running - use this to check that no major compactions get triggered during the day
/ peak hours.

Set your enterprise monitoring alerting schedule to ignore warning status during off-peak scheduled
compaction time.

See also check_hbase_table_compaction_in_progress.py which checks for compactions on a table by table basis.

Tested on Hortonworks HDP 2.3 (HBase 1.1.2) and Apache HBase 1.0.3, 1.1.6, 1.2.2

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import json
import logging
import os
import sys
import traceback
try:
    import requests
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit, jsonpp
    from harisekhon.utils import validate_host, validate_port
    from harisekhon.utils import support_msg_api, isInt
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckHBaseCompactionInProgress(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseCompactionInProgress, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'msg not defined'
        self.ok()

    def add_options(self):
        self.add_hostoption(name='HBase RegionServer', default_host='localhost', default_port=16030)

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        validate_host(host)
        validate_port(port)

        url = 'http://%(host)s:%(port)s/jmx' % locals()
        log.debug('GET %s', url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            qquit('CRITICAL', _)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        if req.status_code != 200:
            qquit('CRITICAL', "%s %s" % (req.status_code, req.reason))
        compaction_queue_size = self.parse(req.content)
        self.msg = 'HBase RegionServer compaction '
        if compaction_queue_size > 0:
            self.warning()
            self.msg += 'in progress'
        else:
            self.msg += 'not in progress'
        self.msg += ', compactionQueueSize = {0}'.format(compaction_queue_size)
        self.msg += ' | compactionQueueSize={0};0;0'.format(compaction_queue_size)

    @staticmethod
    def parse(content):
        try:
            _ = json.loads(content)
            if log.isEnabledFor(logging.DEBUG):
                log.debug('%s', jsonpp(_))
            compaction_queue_size = None
            for bean in _['beans']:
                if bean['name'] == 'Hadoop:service=HBase,name=RegionServer,sub=Server':
                    if log.isEnabledFor(logging.DEBUG):
                        log.debug('found RegionServer section:')
                        log.debug('%s', jsonpp(bean))
                    compaction_queue_size = bean['compactionQueueLength']
                    if not isInt(compaction_queue_size):
                        qquit('UNKNOWN', 'non-integer returned for compactionQueueLength! ' + support_msg_api())
                    return compaction_queue_size
        except ValueError as _:
            qquit('UNKNOWN', _ + ': failed to parse HBase Master jmx info. ' + support_msg_api())
        qquit('UNKNOWN', 'RegionServer mbean not found, double check this is pointing to an HBase RegionServer')


if __name__ == '__main__':
    CheckHBaseCompactionInProgress().main()
