#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-05-04 18:06:55 +0100 (Fri, 04 May 2018)
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

Nagios Plugin to check Linux's Huge Pages kernel setting is disabled

This is often recommended for Big Data & NoSQL systems such as Hadoop and MongoDB as it can cause performance issues

Tested on CentOS 7.4, Debian 9, Ubuntu 16.04, Alpine 3.7

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import re
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import CriticalError, UnknownError, support_msg, log, linux_only
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


# pylint: disable=too-few-public-methods
class CheckLinuxHugepagesDisabled(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckLinuxHugepagesDisabled, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'Linux Kernel Huge Pages = '
        self.ok()

    # must be a method for inheritance purposes
    def run(self):  # pylint: disable=no-self-use
        linux_only()
        regex = re.compile(r'^HugePages_Total:\s+(\d+)\s*$')
        hugepages_total = None
        with open('/proc/meminfo') as meminfo:
            for line in meminfo:
                if 'HugePage' in line:
                    log.debug(line)
                match = regex.match(line)
                if match:
                    hugepages_total = int(match.group(1))  # protected by regex
                    break
            if hugepages_total is None:
                raise UnknownError('HugePages Total not found in /proc/meminfo. {}'.format(support_msg()))
        if hugepages_total == 0:
            self.msg += 'disabled'
        else:
            raise CriticalError(' Huge Pages = enabled. This should be disabled for Big Data ' +
                                'systems such as Hadoop / MongoDB for performance reasons etc...')


if __name__ == '__main__':
    CheckLinuxHugepagesDisabled().main()
