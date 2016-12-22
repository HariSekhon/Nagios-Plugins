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

Nagios Plugin to check the time since last deployment of Blue Talon policies via the Policy Management server REST API

Outputs minutes since last deployment as well as the timestamp returned by the server, and in verbose mode also shows
the user, host and message from the last deployment

Optional thresholds may be applied against the time since last deployment in minutes, defaulting to a lower boundary
(can also use the min:max threshold format) to raise alerts when fresh policy deployments are done. This enables
triggering warning/critical alerts in a stable environment when policies shouldn't be changing that much).

Tested on Blue Talon 2.12.0

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

from datetime import datetime
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
    from harisekhon.utils import log, log_option, qquit, support_msg_api, isList, jsonpp
    from harisekhon.utils import validate_host, validate_port, validate_user, validate_password
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


class CheckBlueTalonPolicyDeploymentAge(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckBlueTalonPolicyDeploymentAge, self).__init__()
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
        self.msg = '{0} version unknown - no message defined'.format(self.software)
        self.ok()

    def add_options(self):
        self.add_hostoption(name=self.software,
                            default_host=self.default_host,
                            default_port=self.default_port)
        self.add_useroption(name=self.software, default_user=self.default_user)
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')
        self.add_thresholds()

    def process_options(self):
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
        self.validate_thresholds(simple='lower', optional=True)

    def run(self):
        log.info('querying %s', self.software)
        url = '{protocol}://{host}:{port}/PolicyManagement/{api_version}/deployments'\
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
        if req.status_code == 400 and req.reason == 'Bad Request':
            qquit('CRITICAL', '{0}: {1} (possibly new install with no deployments yet?)'\
                              .format(req.status_code, req.reason))
        if req.status_code != 200:
            qquit('CRITICAL', '{0}: {1}'.format(req.status_code, req.reason))
        try:
            json_list = json.loads(req.content)
            if log.isEnabledFor(logging.DEBUG):
                print(jsonpp(json_list))
                print('='*80)
            if not isList(json_list):
                raise ValueError('returned content is not a list')
            if not json_list:
                qquit('UNKNOWN', 'no deployments found')
            last_deployment = json_list[0]
            userid = last_deployment['UserId']
            description = last_deployment['Description']
            hostname = last_deployment['HostName']
            timestamp = last_deployment['timestamp']
            last_deploy_datetime = datetime.strptime(timestamp, '%b %d, %Y %H:%M:%S %p')
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', 'error parsing output from {software}: {exception}: {error}. {support_msg}'\
                             .format(software=self.software,
                                     exception=type(_).__name__,
                                     error=_,
                                     support_msg=support_msg_api()))
        timedelta = datetime.now() - last_deploy_datetime
        mins = int(int(timedelta.total_seconds()) / 60)
        self.msg = "{software} last deployment was at '{timestamp}', {mins} mins ago".format(software=self.software,
                                                                                             timestamp=timestamp,
                                                                                             mins=mins)
        self.check_thresholds(mins)
        if self.verbose:
            self.msg += " by user '{userid}', host = '{hostname}', description = '{description}'"\
                        .format(userid=userid, hostname=hostname, description=description)
        self.msg += ' | mins_since_last_deployment={mins}{thresholds}'\
                    .format(mins=mins, thresholds=self.get_perf_thresholds(boundary='lower'))


if __name__ == '__main__':
    CheckBlueTalonPolicyDeploymentAge().main()
