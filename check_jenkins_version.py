#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-06-22 22:29:37 +0200 (Thu, 22 Jun 2017)
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

Nagios Plugin to check the version of Jenkins via the Rest API

The --password switch accepts either a password or an API token

Tested on Jenkins 2.60.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
import os
import re
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from bs4 import BeautifulSoup
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import RestVersionNagiosPlugin
    from harisekhon.utils import log, UnknownError, version_regex, support_msg
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1.1'


# pylint: disable=too-few-public-methods
class CheckJenkinsVersion(RestVersionNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckJenkinsVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Jenkins'
        self.default_port = 8080
        self.path = '/'
        self.ok()

    # Not using python-jenkins due to bug calling get_version() - https://bugs.launchpad.net/python-jenkins/+bug/1578626
    #
    #   File "/Library/Python/2.7/site-packages/jenkins/__init__.py", line 616, in get_version
    #     % self.server)
    # BadHTTPException: Error communicating with server[http://192.168.99.100:8080/]

    # pylint: disable=no-self-use
    def parse(self, req):
        soup = BeautifulSoup(req.content, 'html.parser')
        if log.isEnabledFor(logging.DEBUG):
            log.debug("BeautifulSoup prettified:\n{0}\n{1}".format(soup.prettify(), '='*80))
        version = None
        try:
            _ = soup.find('span', {'class': 'jenkins_ver'})
            log.debug('found span containing jenkins_ver')
            if _:
                version = _.text.strip()
        except (AttributeError, TypeError):
            raise UnknownError('failed to parse output')
        if not version:
            raise UnknownError('failed to retrieve version')
        log.debug('extracting version for Jenkins version string: %s', version)
        _ = re.match(r'Jenkins ver\. ({0})'.format(version_regex), str(version))
        if not _:
            raise UnknownError('failed to parse version string, format may have changed. {0}'.format(support_msg()))
        version = _.group(1)
        return version


if __name__ == '__main__':
    CheckJenkinsVersion().main()
