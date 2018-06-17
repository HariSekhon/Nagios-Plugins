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

Nagios Plugin to check if any Docker Swarm error is reported via the Docker API

Supports TLS with similar options to official 'docker' command

Tested on Docker 18.02

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, jsonpp, CriticalError
    from harisekhon import DockerNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckDockerSwarmError(DockerNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckDockerSwarmError, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'Docker msg not defined yet'

    def check(self, client):
        log.info('running Docker info')
        info = client.info()
        if log.isEnabledFor(logging.DEBUG):
            log.debug(jsonpp(info))
        swarm = info['Swarm']
        if 'Cluster' not in swarm:
            raise CriticalError('Docker is not a member of a Swarm')
        error = swarm['Error']
        if error:
            self.critical()
        else:
            error = 'None'
        self.msg = 'Docker Swarm error = {}'.format(error)


if __name__ == '__main__':
    CheckDockerSwarmError().main()
