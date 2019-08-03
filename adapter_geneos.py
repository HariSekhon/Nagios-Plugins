#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-06-21 16:51:27 +0100 (Tue, 21 Jun 2016)
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

Geneos Adapter program to convert any Nagios Plugin to Geneos CSV format for immediate re-use of all existing
Nagios Plugins from the Advanced Nagios Plugins Collection or elsewhere.

Usage:

Put 'adapter_geneos.py' at the front of any nagios plugin command line and it will call the plugin and translate the
output for you to CSV format for Geneos, with STATUS and DETAIL columns and optionally additional columns for each
perfdata metric if present.

I decided to write this after I worked for a couple of investment banks that were using Geneos instead of a
standard Nagios compatible monitoring system as is more common and I wanted to be able to give production support
access to all the code I've previously developed.

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from adapter_csv import AdapterCSV
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4.1'

# pylint: disable=too-few-public-methods


class AdapterGeneos(AdapterCSV):

    def __init__(self):
        # Python 2.x
        super(AdapterGeneos, self).__init__()
        # Python 3.x
        # super().__init__()
        # special case to make all following args belong to the passed in command and not to this program
        self.headers = ['NAME', 'STATUS', 'DETAILS']

    def output(self):
        output = "{name},{status},{message}"\
                 .format(name=os.path.basename(self.args[0].split()[0]),
                         status=self.status,
                         message=self.message)
        for val in self.perfdata:
            output += self.separator + val
        print(self.separator.join(self.headers))
        print(output)


if __name__ == '__main__':
    # Must always exit zero for Geneos otherwise it won't take the output and will show as raw error
    try:
        AdapterGeneos().main()
    except Exception as _:  # pylint: disable=broad-except
        print(traceback.format_exc(), end='')
        sys.exit(0)
    except SystemExit:
        sys.exit(0)
