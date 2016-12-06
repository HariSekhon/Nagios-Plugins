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

Nagios Plugin to check days until Attivio AIE license expiry by parsing the admin info page

Thresholds are the number of days until expiry

Tested on Attivio 5.1.8

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
# without this Beautiful Soup will fail to encode in debug mode
from __future__ import unicode_literals

from datetime import datetime
import logging
import os
import sys
import traceback
try:
    import requests
    #from requests.auth import HTTPBasicAuth
    from bs4 import BeautifulSoup
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, log_option, qquit, support_msg_api, plural
    from harisekhon.utils import validate_host, validate_port
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckAttivioLicenseExpiry(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckAttivioLicenseExpiry, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'Attivio AIE'
        self.default_host = 'localhost'
        self.default_port = 17000
        self.host = self.default_host
        self.port = self.default_port
        self.protocol = 'http'
        self.msg = '{0} version unknown - no message defined'.format(self.software)
        self.ok()

    def add_options(self):
        self.add_hostoption(name=self.software, default_host=self.default_host, default_port=self.default_port)
        # no authentication is required to access Attivio's AIE system status page
        #self.add_useroption(name=self.software, default_user=self.default_user)
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')
        self.add_thresholds(default_warning=31, default_critical=7)

    def process_options(self):
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        validate_host(self.host)
        validate_port(self.port)
        ssl = self.get_opt('ssl')
        log_option('ssl', ssl)
        if ssl:
            self.protocol = 'https'
        self.validate_thresholds(simple='lower')

    def run(self):
        log.info('querying %s', self.software)
        url = '{protocol}://{host}:{port}/admin/info'\
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
        soup = BeautifulSoup(req.content, 'html.parser')
        if log.isEnabledFor(logging.DEBUG):
            log.debug("BeautifulSoup prettified:\n{0}\n{1}".format(soup.prettify(), '='*80))
        try:
            license_tag = soup.find('td', {'class': 'lic-value'})
            if not license_tag:
                qquit('UNKNOWN', 'failed to find license tag while parsing')
            expiry = license_tag.text.strip()
            license_datetime = datetime.strptime(expiry, '%Y-%m-%d %H:%M:%S')
            delta = license_datetime - datetime.now()
            days = delta.days
            if days < 0:
                qquit('CRITICAL', "license has already expired on '{0}'".format(expiry))
            self.msg = "{software} license expires in {days} day{plural}"\
                       .format(software=self.software, days=days, plural=plural(days))
            self.check_thresholds(days)
            self.msg += ", expiry date = '{expiry}' | days_until_expiry={days}{thresholds}"\
                        .format(expiry=expiry, days=days, thresholds=self.get_perf_thresholds(boundary='lower'))
        except (AttributeError, TypeError) as _:
            qquit('UNKNOWN', 'error parsing output from {software}: {exception}: {error}. {support_msg}'\
                             .format(software=self.software,
                                     exception=type(_).__name__,
                                     error=_,
                                     support_msg=support_msg_api()))


if __name__ == '__main__':
    CheckAttivioLicenseExpiry().main()
