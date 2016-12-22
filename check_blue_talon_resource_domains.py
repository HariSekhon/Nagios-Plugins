#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-05 16:37:57 +0000 (Mon, 05 Dec 2016)
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

Nagios Plugin to check Blue Talon resource domains via the Policy Management server REST API

Currently only determines the number of resource domains, also outputs perfdata.

Warning: the API doesn't expose a count so this program must fetch and count all resource domains
which is an O(n) operation and as such the performance get worse the more resources domains you have.

Optional thresholds may be applied to the number of resources domains

Tested on Blue Talon 2.12.0

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import logging
import json
import os
import sys
import traceback
try:
    import requests
    from requests.auth import HTTPBasicAuth
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, log_option, qquit, support_msg_api, isList, isDict, jsonpp
    from harisekhon.utils import validate_host, validate_port, validate_user, validate_password
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckBlueTalonResourceDomains(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckBlueTalonResourceDomains, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'Blue Talon'
        self.default_host = 'localhost'
        self.default_port = 8111
        self.default_user = 'btadminuser'
        self.default_password = 'P@ssw0rd'
        self.host = self.default_host
        self.port = self.default_port
        self.user = self.default_user
        self.password = None
        self.protocol = 'http'
        self.api_version = '1.0'
        self.msg = '{0}: '.format(self.software)
        self.ok()

    def add_options(self):
        self.add_hostoption(name=self.software,
                            default_host=self.default_host,
                            default_port=self.default_port)
        self.add_useroption(name=self.software, default_user=self.default_user)
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')
        self.add_thresholds()

    def process_options(self):
        self.no_args()
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        self.user = self.get_opt('user')
        self.password = self.get_opt('password')
        validate_host(self.host)
        validate_port(self.port)
        validate_user(self.user)
        validate_password(self.password)
        ssl = self.get_opt('ssl')
        log_option('ssl', ssl)
        if ssl:
            self.protocol = 'https'
        self.validate_thresholds(optional=True)

    def run(self):
        log.info('querying %s', self.software)
        url = '{protocol}://{host}:{port}/PolicyManagement/{api_version}/resource_domains'\
              .format(host=self.host, port=self.port, api_version=self.api_version, protocol=self.protocol)
        log.debug('GET %s', url)
        try:
            req = requests.get(url, auth=HTTPBasicAuth(self.user, self.password))
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
        try:
            json_dict = json.loads(req.content)
            if log.isEnabledFor(logging.DEBUG):
                print(jsonpp(json_dict))
                print('='*80)
            if not isDict(json_dict):
                raise ValueError("non-dict returned by Blue Talon API (got type '{0}')".format(type(json_dict)))
            resource_domains_list = json_dict['resource_domains']
            if not isList(resource_domains_list):
                raise ValueError("non-list returned for 'resource_domains' key by Blue Talon API (got type '{0}')"\
                                 .format(type(resource_domains_list)))
            num_resource_domains = len(resource_domains_list)
            self.msg += '{num_resource_domains} resource domains'\
                        .format(num_resource_domains=num_resource_domains)
            self.check_thresholds(num_resource_domains)
            self.msg += ' | num_resource_domains={num_resource_domains}{perf}'\
                        .format(num_resource_domains=num_resource_domains,
                                perf=self.get_perf_thresholds())
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', 'error parsing output from {software}: {exception}: {error}. {support_msg}'\
                             .format(software=self.software,
                                     exception=type(_).__name__,
                                     error=_,
                                     support_msg=support_msg_api()))


if __name__ == '__main__':
    CheckBlueTalonResourceDomains().main()
