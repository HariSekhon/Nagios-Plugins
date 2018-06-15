#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-06-06 18:48:53 +0100 (Wed, 06 Jun 2018)
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

Nagios Plugin to check for any read only disk mount points on Linux

Raises Critical if there are any read only mounts as this may indicate disk I/O Errors
which have triggered the Linux kernel to remount the disk as read only to protect the filesystem
from corruption

Reads /proc/mounts as this is much more reliable than the 'mount' command which doesn't get updated
in this scenario due to its use of /etc/mtab which merely contains the last mount options executed, not
the current state of mounts as updated by the Linux kernel

See also check_disk_write.pl

Tested on CentOS 7

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
    from harisekhon.utils import log, plural, UnknownError, validate_regex, linux_only, LinuxOnlyException
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4'


class CheckLinuxDiskMountsReadOnly(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckLinuxDiskMountsReadOnly, self).__init__()
        # Python 3.x
        # super().__init__()
        self.include = None
        self.exclude = None
        self.msg = 'Mounts message not defined yet'

    def add_options(self):
        super(CheckLinuxDiskMountsReadOnly, self).add_options()
        self.add_opt('-i', '--include', metavar='regex',
                     help='Inclusion regex of which ' + \
                          'mount points to check (case insensitive)')
        self.add_opt('-e', '--exclude', metavar='regex',
                     help='Exclusion regex of which ' + \
                          'mount points to not check (case insensitive, takes priority over --include)')

    def process_options(self):
        super(CheckLinuxDiskMountsReadOnly, self).process_options()
        self.no_args()
        self.include = self.get_opt('include')
        self.exclude = self.get_opt('exclude')
        if self.include:
            validate_regex(self.include, 'include')
            self.include = re.compile(self.include, re.I)
        if self.exclude:
            validate_regex(self.exclude, 'exclude')
            self.exclude = re.compile(self.exclude, re.I)

    def run(self):
        try:
            linux_only(' as it reads /proc/mounts for more reliable information than the mount command provides' + \
                       ', see --help description for more details')
        except LinuxOnlyException as _:
            raise UnknownError('LinuxOnlyException: {}'.format(_))
        mount_lines = self.get_mounts()
        (num_read_only, num_checked, read_only) = self.parse_mounts(mount_lines)
        self.msg = '{} read only mount point{} out of {} mount point{} checked'\
                   .format(num_read_only, plural(num_read_only), num_checked, plural(num_checked))
        if num_read_only == 0:
            self.ok()
        if num_checked == 0:
            self.warning()
            self.msg += ' (no matching mount points?)'
        if num_read_only > 0:
            self.critical()
            self.msg += '!'
            if self.verbose:
                from pprint import pprint
                pprint(read_only)
                if self.verbose > 1:
                    _ = ['{}({})'.format(mount_point, _type) for mount_point, _type in read_only.iteritems()]
                else:
                    _ = [mount_point for mount_point, _type in read_only.iteritems()]
                self.msg += ' [{}]'.format(', '.join(_))
        self.msg += ' | read_only_mount_points={} mount_points_checked={}'.format(num_read_only, num_checked)

    @staticmethod
    def get_mounts():
        try:
            with open('/proc/mounts', 'r') as _:
                lines = _.readlines()
                if log.isEnabledFor(logging.DEBUG):
                    for line in lines:
                        log.debug('/proc/mounts:  %s', line.rstrip('\n'))
                return lines
        except IOError as _:
            raise UnknownError(_)

    def parse_mounts(self, mount_lines):
        num_checked = 0
        num_read_only = 0
        read_only = {}
        ro_regex = re.compile('^ro,|,ro[,$]')
        ro_system_regex = re.compile('^/proc/|^/sys(?:/.+)?$')
        for mount_line in mount_lines:
            parts = mount_line.split()
            mount_point = parts[1]
            _type = parts[2]
            mount_options = parts[3]
            if ro_system_regex.match(mount_point):
                continue
            if self.include is not None and not self.include.search(mount_point):
                log.info('include regex not matching, skipping mount point %s', mount_point)
                continue
            if self.exclude is not None and self.exclude.search(mount_point):
                log.info('exclude regex matched, skipping mount point %s', mount_point)
                continue
            num_checked += 1
            if ro_regex.search(mount_options):
                num_read_only += 1
                read_only[mount_point] = _type
        return (num_read_only, num_checked, read_only)


if __name__ == '__main__':
    CheckLinuxDiskMountsReadOnly().main()
