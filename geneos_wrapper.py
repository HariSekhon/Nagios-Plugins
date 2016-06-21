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

Geneos Wrapper program to convert any Nagios Plugin to Geneos format for immediate re-use to all existing
Nagios Plugins from the Advanced Nagios Plugins Collection or elsewhere.

Usage it simple, just prepend this program to the nagios plugin command line and it will call the plugin and translate
the output for you to CSV format for Geneos.

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import logging
import os
import re
import sys
import subprocess
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import CLI
    from harisekhon.utils import prog, log, ERRORS
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class GeneosWrapper(CLI):

    def __init__(self):
        # Python 2.x
        super(GeneosWrapper, self).__init__()
        # Python 3.x
        # super().__init__()
        # special case to make all following args belong to the passed in command and not to this program
        self._CLI__parser.disable_interspersed_args()
        self._CLI__parser.set_usage('{prog} [options] <check_nagios_plugin_name> <plugin_args> ...'.format(prog=prog))
        self.timeout_default = 60
        log.setLevel(logging.ERROR)
        self.returncodes = {}
        for key in ERRORS:
            self.returncodes[ERRORS[key]] = key
        self.perfdata_regex = re.compile(r'(\d+(?:\.\d+))(\w{1,2}|%)')

    # @Overrride to prevent injecting the usual default opts
    # update: allowing default opts now as it's handy to have multiple verbosity to see the output being printed
    #def add_default_opts(self):
    #    pass

    def run(self):
        cmd = ' '.join(self.args)
        if not cmd:
            self.usage()
        log.info("cmd: %s", cmd)
        status = "UNKNOWN"
        msg = "<no message defined>"
        try:
            proc = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            (stdout, _) = proc.communicate()
            returncode = proc.wait()
            if returncode > 255:
                returncode = int(returncode % 256)
            if returncode in self.returncodes:
                status = self.returncodes[returncode]
            else:
                log.warn("non-standard exit code detected, resetting to CRITICAL")
                status = "CRITICAL"
            msg = stdout
        except subprocess.CalledProcessError as _:
            status = "UNKNOWN"
            msg = str(_)
        except OSError as _:
            status = "UNKNOWN"
            msg = "OSError: '{0}' when running '{1}'".format(_, cmd)
        msg = re.sub(r'\s*(?:OK|WARNING|CRITICAL|UNKNOWN)\s*(?:[\w\s]+)?:', '', msg, 1, re.I)
        msg = re.sub(r'\n', r' \\n ', msg)
        msg = re.sub(r',+', '... ', msg)
        perfdata_raw = None
        perfdata = []
        headers = [ "STATUS", "DETAIL" ]
        if '|' in msg:
            msg, perfdata_raw = msg.split('|', 1)
        if perfdata_raw:
            for item in perfdata_raw.split():
                if '=' in item:
                    header, data = item.split('=', 1)
                    header = header.strip('"')
                    header = header.strip('"')
                    data = data.split(';')[0]
                    match = self.perfdata_regex.search(data)
                    if match:
                        if match.group(2):
                            header += " ({0})".format(match.group(2))
                        headers += [header.upper()]
                        perfdata += [match.group(1)]
        msg = msg.strip()
        output = "{status},{detail}".format(status=status, detail=msg)
        for p in perfdata:
            output += ',' + p
        print(','.join(headers))
        print(output)


if __name__ == '__main__':
    GeneosWrapper().main()
    # Must always exit zero for Geneos otherwise it won't take the output and will show as raw error
    sys.exit(0)
