#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-03-05 19:10:02 +0000 (Mon, 05 Mar 2018)
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

Nagios Plugin to check Docker version via the Docker API

Can optionally test the version matches a regex

Also outputs the Docker API version

Supports TLS with similar options to official 'docker' command

Tested on Docker 18.02

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
import os
import re
import sys
#import time
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, UnknownError, validate_regex, isVersionLax, support_msg_api, jsonpp
    from harisekhon import DockerNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4'


class CheckDockerVersion(DockerNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckDockerVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.expected = None
        self.msg = 'Docker msg not defined yet'

    def add_options(self):
        self.add_opt('-e', '--expected', help='Expected version regex (optional)')
        self.add_docker_options()

    def process_options(self):
        self.expected = self.get_opt('expected')
        if self.expected is not None:
            validate_regex(self.expected)
            log.info('expected version regex: %s', self.expected)

    def check(self, client):
        log.info('getting Docker version')
        _ = client.version()
        if log.isEnabledFor(logging.DEBUG):
            log.debug((jsonpp(_)))
        version = _['Version']
        if not isVersionLax(version):
            raise UnknownError('Docker version unrecognized \'{}\'. {}'\
                               .format(version, support_msg_api()))
        self.msg = 'Docker version = {}'.format(version)
        if self.expected is not None:
            log.info("verifying version against expected regex '%s'", self.expected)
            if re.match(self.expected, str(version)):
                log.info('version regex matches retrieved version')
            else:
                log.info('version regex does not match retrieved version')
                self.msg += " (expected '{}')".format(self.expected)
                self.critical()
        self.msg += ', API version = {}'.format(_['ApiVersion'])


if __name__ == '__main__':
    CheckDockerVersion().main()
