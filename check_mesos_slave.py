#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-02-19 19:21:30 +0000 (Fri, 19 Feb 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check a given Mesos slave is registered with the Mesos Master

Tested on Mesos 0.23 and 0.24

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import json
import logging
import os
import re
import sys
import traceback
try:
    import requests
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
libdir = os.path.abspath(os.path.join(os.path.dirname(__file__), 'pylib'))
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit
    from harisekhon.utils import validate_host, validate_port, isJson, support_msg_api, jsonpp, dict_lines
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.2'


class CheckMesosSlave(NagiosPlugin):

#    def __init__(self):
#        # Python 2.x
#        super(CheckMesosSlave, self).__init__()
#        # Python 3.x
#        # super().__init__()

    def add_options(self):
        self.add_hostoption(name='Mesos Master', default_host='localhost', default_port=5050)
        self.add_opt('-s', '--slave', help='Mesos slave hostname or IP to check is registered with Mesos Master')
        self.add_opt('-l', '--list-slaves', action='store_true', help='List slaves and exit')

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        slave = self.get_opt('slave')
        list_slaves = self.get_opt('list_slaves')
        validate_host(host)
        validate_port(port)
        if not list_slaves:
            validate_host(slave, 'slave')

        url = 'http://%(host)s:%(port)s/master/slaves' % locals()
        log.debug('GET %s', url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            qquit('CRITICAL', _)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n{0}\n{1}\n{2}".format('='*80, req.content.strip(), '='*80))
        if req.status_code != 200:
            if req.status_code == 404:
                qquit('CRITICAL', '%s %s (did you point this at the correct Mesos Master?)'
                                  % (req.status_code, req.reason))
            qquit('CRITICAL', "Non-200 response! %s %s" % (req.status_code, req.reason))
        content = req.content
        if not isJson(content):
            qquit('UNKNOWN', 'invalid JSON returned by Mesos Master')
        data = json.loads(content)
        if log.isEnabledFor(logging.DEBUG):
            log.debug('\n%s', jsonpp(data))
        slaves = {}
        regex = re.compile(r'^slave\(\d+\)\@(.+):\d+')
        try:
            for item in data['slaves']:
                match = regex.match(item['pid'])
                if match:
                    slaves[item['hostname']] = match.group(1)
                else:
                    slaves[item['hostname']] = item['pid']
        except KeyError:
            qquit('UNKNOWN', 'failed to parse slaves from Mesos API output. {0}'.format(support_msg_api))
        if list_slaves:
            qquit('UNKNOWN', 'Slaves list:\n\n{0}'.format(dict_lines(slaves)))
        log.info('found slaves:\n\n{0}\n'.format(dict_lines(slaves)))
        slave = slave.lower()
        for _ in slaves:
            if slave == _.lower() or slave == slaves[_].lower():
                qquit('OK', "Mesos slave '{0}' registered with master".format(slave))
                break
        else:
            qquit('CRITICAL', "Mesos slave '{0}' not registered with master".format(slave))


if __name__ == '__main__':
    CheckMesosSlave().main()
