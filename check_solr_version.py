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

Nagios Plugin to check the deployed version of Solr matches what's expected.

This is also used in the accompanying test suite to ensure we're checking the right version of Solr
for compatibility for all my other Solr / SolrCloud nagios plugins.

Tested on Solr 4.10.4, 5.5.0, 6.0.0

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
    from harisekhon.utils import log, CriticalError, UnknownError, support_msg_api
    from harisekhon.utils import validate_host, validate_port, validate_regex, isVersion
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckSolrVersion(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckSolrVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'Solr version unknown - no message defined'

    def add_options(self):
        self.add_hostoption(name='Solr', default_host='localhost', default_port=8983)
        self.add_opt('-e', '--expected', help='Expected version regex (optional)')

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        validate_host(host)
        validate_port(port)
        expected = self.get_opt('expected')
        if expected is not None:
            validate_regex(expected)
            log.info('expected version regex: %s', expected)

        url = 'http://%(host)s:%(port)s/solr/admin/info/system' % locals()
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
            version = soup.find('str', {'name':'solr-spec-version'}).text
        except (AttributeError, TypeError) as _:
            raise UnknownError('failed to find parse Solr output. {0}\n{1}'.
                               format(support_msg_api(), traceback.format_exc()))
        if not version:
            raise UnknownError('Solr version not found in output. {0}'.format(support_msg_api()))
        if not isVersion(version):
            raise UnknownError('Solr version unrecognized \'{0}\'. {1}'.format(version, support_msg_api()))
        self.ok()
        self.msg = 'Solr version = {0}'.format(version)
        if expected is not None and not re.search(expected, version):
            self.msg += " (expected '{0}')".format(expected)
            self.critical()


if __name__ == '__main__':
    CheckSolrVersion().main()
