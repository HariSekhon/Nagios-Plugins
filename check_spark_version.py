#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-05-23 17:49:21 +0100 (Mon, 23 May 2016)
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

Nagios Plugin to check the deployed version of Apache Spark standalone matches what's expected.

This is also used in the accompanying test suite to ensure we're checking the right version of Spark

Tested on Spark 1.3, 1.4, 1.5, 1.6

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import logging
import os
import re
import sys
import traceback
try:
    from bs4 import BeautifulSoup
    import requests
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, CriticalError, UnknownError, support_msg_api, prog, space_prefix
    from harisekhon.utils import validate_host, validate_port, validate_regex, isVersion
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckSparkVersion(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckSparkVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.software = 'Spark'
        name = ''
        default_port = None
        if re.search('master', prog, re.I):
            name = 'Master'
            default_port = 8080
        elif re.search('worker|slave', prog, re.I):
            name = 'Worker'
            default_port = 8081
        self.name = space_prefix(name)
        self.default_port = default_port
        self.msg = '{0} version unknown - no message defined'.format(self.software)

    def add_options(self):
        self.add_hostoption(name="%(software)s%(name)s" % self.__dict__,
                            default_host='localhost',
                            default_port=self.default_port)
        self.add_opt('-e', '--expected', help='Expected version regex (optional)')

    def run(self):
        self.ok()
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        validate_host(host)
        validate_port(port)
        expected = self.get_opt('expected')
        if expected is not None:
            validate_regex(expected)
            log.info('expected version regex: %s', expected)

        log.info('querying %s%s', self.software, self.name)
        url = 'http://%(host)s:%(port)s/home' % locals()
        log.debug('GET %s' % url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            raise CriticalError(_)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        if req.status_code != 200:
            raise CriticalError("%s %s" % (req.status_code, req.reason))
        soup = BeautifulSoup(req.content, 'html.parser')
        if log.isEnabledFor(logging.DEBUG):
            log.debug("BeautifulSoup prettified:\n{0}\n{1}".format(soup.prettify(), '='*80))
        try:
            #version = soup.find('span', {'class': 'version'}).text
            version = soup.find('span', class_='version').text
        except (AttributeError, TypeError) as _:
            raise UnknownError('failed to find parse {0} output. {1}\n{2}'.
                               format(self.software, support_msg_api(), traceback.format_exc()))
        if not version:
            raise UnknownError('{0} version not found in output. {1}'.format(self.software, support_msg_api()))
        if not isVersion(version):
            raise UnknownError('{0} version unrecognized \'{1}\'. {2}'.
                               format(self.software, version, support_msg_api()))
        self.msg = '{0}{1} version = {2}'.format(self.software, self.name, version)
        if expected is not None and not re.search(expected, version):
            self.msg += " (expected '{0}')".format(expected)
            self.critical()


if __name__ == '__main__':
    CheckSparkVersion().main()
