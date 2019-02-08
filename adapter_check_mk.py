#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-14 00:39:25 +0000 (Wed, 14 Dec 2016)
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

Adapter program to convert any Nagios Plugin to Check MK local check format for immediate re-use of all existing
Nagios Plugins from the Advanced Nagios Plugins Collection or elsewhere.

Usage:

Put 'adapter_check_mk.py' at the front of any nagios plugin command line and it will call the plugin and
translate the output for you to Check MK format.

Alternatively you can feed it literal output from a nagios plugin combined with the --result <exitcode> switch.

Nagios Format:

message | perfdata

statuscode is the exit code

Check MK format (http://mathias-kettner.de/checkmk_localchecks.html):

statuscode name perfdata message

Since the format of Check MK local checks doesn't permit spaces in anything except the final message data, any spaces
in the check name or perfdata will be changed to underscores and multiple perfdata items will result in multiple lines
of output to separate out each perfdata item one per line

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import re
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, ERRORS, isFloat
    from adapter_csv import AdapterCSV
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4'


class AdapterCheckMK(AdapterCSV):

    def __init__(self):
        # Python 2.x
        super(AdapterCheckMK, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = None
        self.space_regex = re.compile(r'\s+')

    def add_options(self):
        self.add_opt('-n', '--name', metavar='<check_name>',
                     help='Name of the check (defaults to the basename of the plugin)')
        super(AdapterCheckMK, self).add_options()

    def process_options(self):
        self.name = self.get_opt('name')
        if not self.name:
            for arg in self.args:
                arg = os.path.basename(arg)
                if arg and arg[0] != '-' and \
                   not self.is_interpreter(arg) and \
                   arg not in ERRORS and \
                   not isFloat(arg):
                    self.name = arg
                    break
        if not self.name:
            self.usage('--name not defined')
        self.name = self.space_regex.sub('_', self.name)
        log.info('name = %s', self.name)

    # handles if you call plugin with explicit numbered interpreter eg. python2.7 etc...
    @staticmethod
    def is_interpreter(arg):
        for prog in ('perl', 'python', 'ruby', 'groovy', 'jython'):
            if arg[0:len(prog)] == prog:
                return True
        return False

    def output(self):
        perfdata = ""
        for key, val in zip(self.headers[2:], self.perfdata):
            perfdata += '{key}={val}|'.format(key=self.space_regex.sub('_', key),
                                              val=val)
        perfdata = perfdata.rstrip('|')
        if not perfdata:
            perfdata = '-'
        output = '{status} {name} {perfdata} {message}'\
                 .format(status=ERRORS[self.status],
                         name=self.name,
                         perfdata=perfdata,
                         message=self.message)
        print(output)


if __name__ == '__main__':
    AdapterCheckMK().main()
    # Must always exit zero for Geneos otherwise it won't take the output and will show as raw error
    sys.exit(0)
