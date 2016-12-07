#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-06 16:37:08 +0000 (Tue, 06 Dec 2016)
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

Nagios Plugin to check Attivio AIE system health including any nodes down, performance monitoring down,
warning and fatal error counts as well as acknowledged counts

Nodes Down and Fatal errors result in CRITICAL status

Warnings or performance monitoring down result in WARNING status

Tested on Attivio 5.1.8

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
import json
import os
import sys
import traceback
try:
    import requests
    #from requests.auth import HTTPBasicAuth
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, log_option, qquit, support_msg_api, isDict, isInt, jsonpp
    from harisekhon.utils import validate_host, validate_port
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckAttivioSystemHealth(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAttivioSystemHealth, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'Attivio AIE'
        self.default_host = 'localhost'
        self.default_port = 17000
        self.host = self.default_host
        self.port = self.default_port
        self.protocol = 'http'
        self.msg = '{0} system health: '.format(self.software)
        self.ok()

    def add_options(self):
        self.add_hostoption(name=self.software, default_host=self.default_host, default_port=self.default_port)
        # no authentication is required to access Attivio's AIE system status page
        #self.add_useroption(name=self.software, default_user=self.default_user)
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')

    def process_options(self):
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        validate_host(self.host)
        validate_port(self.port)
        ssl = self.get_opt('ssl')
        log_option('ssl', ssl)
        if ssl:
            self.protocol = 'https'

    def run(self):
        log.info('querying %s', self.software)
        url = '{protocol}://{host}:{port}/admin/systemHealth?cmd=systemhealth&format=json&cache=false'\
              .format(host=self.host, port=self.port, protocol=self.protocol)
        log.debug('GET %s', url)
        try:
            req = requests.get(url)
            #req = requests.get(url, auth=HTTPBasicAuth(self.user, self.password))
        except requests.exceptions.RequestException as _:
            errhint = ''
            if 'BadStatusLine' in str(_.message):
                errhint = ' (possibly connecting to an SSL secured port without using --ssl?)'
            elif self.protocol == 'https' and 'unknown protocol' in str(_.message):
                errhint = ' (possibly connecting to a plain HTTP port with the -S / --ssl switch enabled?)'
            qquit('CRITICAL', str(_) + errhint)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        if req.status_code != 200:
            qquit('CRITICAL', '{0}: {1}'.format(req.status_code, req.reason))
        self.parse_results(req.content)

    def parse_results(self, content):
        try:
            json_dict = json.loads(content)
            if log.isEnabledFor(logging.DEBUG):
                print(jsonpp(content))
                print('='*80)
            # looks like syshealthok child div is only there in browser, but give syshealthspin in code
            #if soup.find('div', id='syshealthstatus').find('div', id='syshealthok'):
            if not isDict(json_dict):
                raise ValueError("non-dict returned by Attivio AIE server response (type was '{0}')"\
                                 .format(type(json_dict)))
            # if this is true from warnings would ruin the more appropriate warnings check
            #if json_dict['haserrors']:
            #    self.critical()
            #    self.msg += 'errors detected, '
            nodes_down = json_dict['nodesdown']
            warnings = json_dict['warnings']
            fatals = json_dict['fatals']
            acknowledged = json_dict['acknowledged']
            if not isInt(nodes_down):
                raise ValueError('non-integer returned for nodes down count by Attivio AIE')
            if not isInt(warnings):
                raise ValueError('non-integer returned for warnings count by Attivio AIE')
            if not isInt(fatals):
                raise ValueError('non-integer returned for fatals count by Attivio AIE')
            if not isInt(acknowledged):
                raise ValueError('non-integer returned for acknowledged count by Attivio AIE')
            nodes_down = int(nodes_down)
            warnings = int(warnings)
            fatals = int(fatals)
            acknowledged = int(acknowledged)
            if nodes_down > 0 or fatals > 0:
                self.critical()
            elif warnings > 0:
                self.warning()
            self.msg += '{nodes_down} nodes down, {fatals} fatals, {warnings} warnings, {acknowledged} acknowledged'\
                        .format(nodes_down=nodes_down, fatals=fatals, warnings=warnings, acknowledged=acknowledged)
            if json_dict['perfmondown']:
                self.warning()
                self.msg += ', warning: performance monitoring down'
            self.msg += ' | nodes_down={nodes_down} fatals={fatals} warnings={warnings} acknowledged={acknowledged}'\
                        .format(nodes_down=nodes_down, fatals=fatals, warnings=warnings, acknowledged=acknowledged)
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', 'error parsing output from {software}: {exception}: {error}. {support_msg}'\
                             .format(software=self.software,
                                     exception=type(_).__name__,
                                     error=_,
                                     support_msg=support_msg_api()))


if __name__ == '__main__':
    CheckAttivioSystemHealth().main()
