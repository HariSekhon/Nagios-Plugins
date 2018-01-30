#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-01-30 11:01:00 +0000 (Tue, 30 Jan 2018)
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

Nagios Plugin to check the version of a Prometheus server

Tested on Prometheus 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
import os
import sys
import traceback
try:
    from bs4 import BeautifulSoup
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, support_msg, UnknownError
    from harisekhon import RestVersionNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckPrometheusVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckPrometheusVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Prometheus'
        self.default_port = 9090
        self.path = '/status'
        self.auth = False
        self.ok()

    # pylint: disable=no-self-use
    def parse(self, req):
        soup = BeautifulSoup(req.content, 'html.parser')
        if log.isEnabledFor(logging.DEBUG):
            log.debug("BeautifulSoup prettified:\n{0}\n{1}".format(soup.prettify(), '='*80))
        version = None
        try:
            _ = soup.find('th', {'scope': 'row'})
            if _.text.strip() == 'Version':
                version = _.find_next_sibling('td').text
        except (AttributeError, TypeError):
            raise UnknownError('failed to parse output. {}'.format(support_msg()))
        if not version:
            raise UnknownError('failed to retrieve version')
        return version


if __name__ == '__main__':
    CheckPrometheusVersion().main()
