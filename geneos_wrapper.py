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

Geneos Wrapper program to convert any Nagios Plugin to Geneos CSV format for immediate re-use of all existing
Nagios Plugins from the Advanced Nagios Plugins Collection or elsewhere.

Usage it simple, just put 'geneos_wrapper.py' at the front of any nagios plugin command line and it will call
the plugin and translate the output for you to CSV format for Geneos, with a STATUS and DETAIL field and
optionally additional fields for each perfdata metric.

I decided to write this after I worked for a couple of investment banks that were using Geneos instead of a Nagios compatible monitoring system as is more common and I wanted to be able to give production support access to all the code I've previously developed.

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
        self.perfdata_regex = re.compile(r'(\d+(?:\.\d+)?)([A-Za-z]{1,2}|%)?')

    # @Overrride to prevent injecting the usual default opts
    # update: allowing default opts now as it's handy to have multiple verbosity levels for debugging
    #def add_default_opts(self):
    #    pass

    def run(self):
        cmd = ' '.join(self.args)
        if not cmd:
            self.usage()
        log.info("cmd: %s", cmd)
        status = "UNKNOWN"
        detail = "<None>"
        try:
            proc = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            (stdout, stderr) = proc.communicate()
            log.debug("stdout: %s", stdout)
            log.debug("stderr: %s", stderr)
            returncode = proc.wait()
            log.debug("returncode: %s", returncode)
            if returncode > 255:
                log.debug("mod 256")
                returncode = int(returncode % 256)
            if returncode in self.returncodes:
                log.debug("translating exit code '%s' => '%s'", returncode, self.returncodes[returncode])
                status = self.returncodes[returncode]
            else:
                log.warn("non-standard exit code detected, resetting to CRITICAL")
                status = "CRITICAL"
            detail = stdout
        except subprocess.CalledProcessError as _:
            log.warn("subprocess.CalledProcessError, resetting to UNKNOWN")
            status = "UNKNOWN"
            detail = str(_)
        except OSError as _:
            log.warn("OSError, resetting to UNKNOWN")
            status = "UNKNOWN"
            detail = "OSError: '{0}' when running '{1}'".format(_, cmd)
        log.debug("raw detail: %s", detail)
        detail = re.sub(r'(?:[\w\s]*?\s)?(?:OK|WARNING|CRITICAL|UNKNOWN)(?:\s[\w\s]*?)?:', '', detail, 1, re.I)
        detail = detail.rstrip('\n')
        detail = re.sub(r'\r', r'', detail)
        detail = re.sub(r'\n', r' \\n ', detail)
        detail = re.sub(r',+', '... ', detail)
        perfdata_raw = None
        perfdata = []
        headers = [ "STATUS", "DETAIL" ]
        if '|' in detail:
            detail, perfdata_raw = detail.split('|', 1)
        if perfdata_raw:
            log.debug("raw perfdata: %s", perfdata_raw)
            for item in perfdata_raw.split():
                if '=' in item:
                    header, data = item.split('=', 1)
                    header = header.strip('"')
                    header = header.strip('"')
                    data = data.split(';')[0]
                    match = self.perfdata_regex.search(data)
                    if match:
                        val = match.group(1)
                        log.debug("found numeric value '%s' in item '%s'", val, item)
                        if match.group(2):
                            units = match.group(2)
                            log.debug("found units '%s' in item '%s'", units, item)
                            header += " ({0})".format(units)
                        headers += [header.upper()]
                        perfdata += [val]
                    else:
                        log.warn("no valid numeric value to extract found in perfdata item '%s'", item)
                else:
                    log.warn("no key=value format detected in item '%s'", item)
        detail = detail.strip()
        output = "{status},{detail}".format(status=status, detail=detail)
        for p in perfdata:
            output += ',' + p
        print(','.join(headers))
        print(output)


if __name__ == '__main__':
    GeneosWrapper().main()
    # Must always exit zero for Geneos otherwise it won't take the output and will show as raw error
    sys.exit(0)
