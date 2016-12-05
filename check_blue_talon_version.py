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

Nagios Plugin to check the deployed version of Blue Talon via the Policy Management server REST API

Tested on Blue Talon 3.1.3

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import json
import os
import re
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
    from harisekhon.utils import log, qquit, support_msg_api, isDict
    from harisekhon.utils import isVersion
    from harisekhon import VersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckBlueTalonVersion(VersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckBlueTalonVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'Blue Talon'
        self.default_host = 'localhost'
        self.default_port = 8111
        self.api_version = '1.0'
        self.msg = '{0} version unknown - no message defined'.format(self.software)
        self.ok()

    def run(self):
        (build_version, api_version, update_date) = self.get_version()
        self.check_version(build_version)
        if not isVersion(api_version):
            qquit('UNKNOWN', '{0} api version unrecognized \'{1}\'. {2}'\
                             .format(self.software, api_version, support_msg_api()))
        if api_version != self.api_version:
            qquit('UNKNOWN', "unexpected API version '{0}' returned (expected '{1}')"\
                             .format(api_version, self.api_version))
        self.msg += ', api version = {0}, update date = {1}'.format(api_version, update_date)

    def get_version(self):
        log.info('querying %s', self.software)
        url = 'http://{host}:{port}/PolicyManagement/{api_version}/version'.format(host=self.host,
                                                                                   port=self.port,
                                                                                   api_version=self.api_version)
        log.debug('GET %s', url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            qquit('CRITICAL', _)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        try:
            json_dict = json.loads(req.content)
            if not isDict(json_dict):
                raise ValueError
            company_name = json_dict['company_name']
            company_website = json_dict['company_website']
            regex = re.compile(r'Blue\s*Talon', re.I)
            if not regex.match(company_name) and \
               not regex.match(company_website):
                qquit('UNKNOWN', 'Blue Talon name was not found in either company_name or company_website fields' \
                               + ', are you definitely querying a Blue Talon server?')
            build_version = json_dict['build_version']
            api_version = json_dict['api_version']
            update_date = json_dict['update_date']
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', 'error parsing output from {software}: {exception}: {error}. {support_msg}'\
                             .format(software=self.software,
                                     exception=type(_).__name__,
                                     error=_,
                                     support_msg=support_msg_api()))
        return (build_version, api_version, update_date)


if __name__ == '__main__':
    CheckBlueTalonVersion().main()
