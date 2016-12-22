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

Outputs the version and update date.

Optional --expected regex may be used to check the version is as expected.

Verbose mode additionally outputs revision, build, schema revision and api version

Tested on Blue Talon 2.12.0

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import logging
import json
import os
import re
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
    from harisekhon.utils import log, log_option, qquit, support_msg_api, isVersion, isList, isDict, jsonpp
    from harisekhon.utils import validate_host, validate_port, validate_user, validate_password
    from harisekhon import VersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckBlueTalonVersion(VersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckBlueTalonVersion, self).__init__()
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
        self.expected = None
        self.protocol = 'http'
        self.api_version = '1.0'
        self.msg = '{0} version unknown - no message defined'.format(self.software)
        self.ok()

    def add_options(self):
        super(CheckBlueTalonVersion, self).add_options()
        self.add_useroption(name=self.software, default_user=self.default_user)
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')

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
        self.process_expected_version_option()

    def run(self):
        (build_version, extra_info) = self.get_version()
        self.check_version(build_version)
        self.msg += extra_info

    def get(self):
        log.info('querying %s', self.software)
        url = '{protocol}://{host}:{port}/PolicyManagement/{api_version}/version'\
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
        return req.content

    def get_version(self):
        content = self.get()
        try:
            json_list = json.loads(content)
            if log.isEnabledFor(logging.DEBUG):
                print(jsonpp(json_list))
                print('='*80)
            if not isList(json_list):
                raise ValueError("non-list returned by API (is type '{0}')".format(type(json_list)))
            json_dict = json_list[0]
            if not isDict(json_dict):
                raise ValueError("non-dict found inside returned list (is type '{0}')".format(type(json_dict)))
            company_name = json_dict['company_name']
            company_website = json_dict['company_website']
            regex = re.compile(r'Blue\s*Talon', re.I)
            if not regex.match(company_name) and \
               not regex.match(company_website):
                qquit('UNKNOWN', 'Blue Talon name was not found in either company_name or company_website fields' \
                               + ', are you definitely querying a Blue Talon server?')
            build_version = json_dict['build_version']
            update_date = json_dict['update_date']
            api_version = json_dict['api_version']
            if not isVersion(api_version):
                qquit('UNKNOWN', '{0} api version unrecognized \'{1}\'. {2}'\
                                 .format(self.software, api_version, support_msg_api()))
            if api_version != self.api_version:
                qquit('UNKNOWN', "unexpected API version '{0}' returned (expected '{1}')"\
                                 .format(api_version, self.api_version))
            if self.verbose:
                extra_info = ' revision {revision} build {build}, schema revision = {schema_revision}'\
                              .format(revision=json_dict['revision_no'],
                                      build=json_dict['build_no'],
                                      schema_revision=json_dict['schema_revision'])
                extra_info += ', api version = {api_version}, update date = {update_date}'\
                              .format(api_version=api_version, update_date=update_date)
            else:
                extra_info = ', update date = {update_date}'.format(update_date=update_date)
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', 'error parsing output from {software}: {exception}: {error}. {support_msg}'\
                             .format(software=self.software,
                                     exception=type(_).__name__,
                                     error=_,
                                     support_msg=support_msg_api()))
        return (build_version, extra_info)


if __name__ == '__main__':
    CheckBlueTalonVersion().main()
