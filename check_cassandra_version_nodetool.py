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

Nagios Plugin to check the deployed version of Cassandra matches what's expected.

This version uses 'nodetool' which must be in the $PATH

This is also used in the accompanying test suite to ensure we're checking the right version of Cassandra
for compatibility for all my other Cassandra nagios plugins.

Tested on Cassandra 1.2, 2.0, 2.1, 2.2, 3.0, 3.5, 3.6, 3.7, 3.9, 3.10, 3.11

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import re
import subprocess
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, CriticalError, UnknownError, support_msg
    from harisekhon.utils import validate_regex, isVersion, version_regex
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckCassandraVersion(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckCassandraVersion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'Cassandra version unknown - no message defined'
        self.version_regex = re.compile(r'^\s*ReleaseVersion:\s+({0})'.format(version_regex))

    def add_options(self):
        self.add_opt('-e', '--expected', help='Expected version regex (optional)')

    def run(self):
        expected = self.get_opt('expected')
        if expected is not None:
            validate_regex(expected)
            log.info('expected version regex: %s', expected)
        cmd = 'nodetool version'
        log.debug('cmd: ' + cmd)
        proc = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (stdout, _) = proc.communicate()
        log.debug('stdout: ' + str(stdout))
        returncode = proc.wait()
        log.debug('returncode: ' + str(returncode))
        if returncode != 0 or (stdout is not None and 'Error' in stdout):
            raise CriticalError('nodetool returncode: {0}, output: {1}'.format(returncode, stdout))
        version = None
        for line in str(stdout).split('\n'):
            match = self.version_regex.match(line)
            if match:
                version = match.group(1)
        if not version:
            raise UnknownError('Cassandra version not found in output. Nodetool output may have changed. {0}'.
                               format(support_msg()))
        if not isVersion(version):
            raise UnknownError('Cassandra version unrecognized \'{0}\'. {1}'.format(version, support_msg()))
        self.ok()
        self.msg = 'Cassandra version = {0}'.format(version)
        if expected is not None and not re.search(expected, version):
            self.msg += " (expected '{0}')".format(expected)
            self.critical()


if __name__ == '__main__':
    CheckCassandraVersion().main()
