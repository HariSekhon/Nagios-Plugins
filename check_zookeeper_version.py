#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-05-25 11:40:55 +0100 (Wed, 25 May 2016)
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

Nagios Plugin to check the deployed version of ZooKeeper matches what's expected.

This is also used in the accompanying test suite to ensure we're checking the right version of ZooKeeper
and to avoid the check_zookeeper.pl which needs mntr not available in ZooKeeper 3.3

Tested on ZooKeeper 3.3.6, 3.4.8

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import re
import socket
import sys
import traceback
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


class CheckZooKeeperVersion(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckZooKeeperVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'ZooKeeper version unknown - no message defined'
        self.version_line_regex = re.compile(r'^zookeeper.version=(\d+\.\d+\.\d+)')

    def add_options(self):
        self.add_hostoption(name='ZooKeeper', default_host='localhost', default_port=2181)
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
        data = None
        try:
            #conn = socket.create_connection('%(host)s:%(port)s' % locals(), timeout=self.timeout/2)
            #conn = socket.create_connection('%s:%s' % (host, port), timeout=self.timeout/2)
            conn = socket.create_connection((host, port), timeout=self.timeout/2)
            conn.sendall('envi')
            data = conn.recv(1024)
            conn.close()
        except socket.error as _:
            raise CriticalError('Failed to connect to ZooKeeper: ' + str(_))
        version = None
        log.debug(data.strip())
        for line in data.split('\n'):
            _ = self.version_line_regex.match(line)
            if _:
                version = _.group(1)
                break
        if not version:
            raise UnknownError('ZooKeeper version not found in output. {0}'.format(support_msg_api()))
        if not isVersion(version):
            raise UnknownError('ZooKeeper version unrecognized \'{0}\'. {1}'.format(version, support_msg_api()))
        self.ok()
        self.msg = 'ZooKeeper version = {0}'.format(version)
        if expected is not None and not re.match(expected, version):
            self.msg += " (expected '{0}')".format(expected)
            self.critical()


if __name__ == '__main__':
    CheckZooKeeperVersion().main()
