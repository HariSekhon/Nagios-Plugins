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

Usage is simple - just put 'geneos_wrapper.py' at the front of any nagios plugin command line and it will call
the plugin and translate the output for you to CSV format for Geneos, with STATUS and DETAIL columns and
optionally additional columns for each perfdata metric if present.

I decided to write this after I worked for a couple of investment banks that were using Geneos instead of a
standard Nagios compatible monitoring system as is more common and I wanted to be able to give production support
access to all the code I've previously developed.

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
__version__ = '0.3.1'


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
        self.status = "UNKNOWN"
        self.detail = "<None>"
        self.perfdata = []
        self.headers = ["STATUS", "DETAIL"]

    # @Overrride to prevent injecting the usual default opts
    # update: allowing default opts now as it's handy to have multiple verbosity levels for debugging
    #def add_default_opts(self):
    #    pass

    def add_options(self):
        self.add_opt('-s', '--shell', action='store_true',
                     help='Use Shell to execute args (default: false)')

    def run(self):
        cmdline = ' '.join(self.args)
        if not cmdline:
            self.usage()
        self.cmd(cmdline)
        self.clean_detail()
        self.process_perfdata()
        self.output()

    #@staticmethod
    def clean_detail(self):
        detail = self.detail
        detail = re.sub(r'\s*(?:[\w\s]+?\s)?(?:OK|WARNING|CRITICAL|UNKNOWN)(?:\s[\w\s]+?)?\s*:\s*', '', detail, 1, re.I)
        if re.search('^Hari Sekhon', detail):
            _ = re.search('^usage:', detail, re.M)
            if _:
                log.debug('stripping off my extended plugin description header up to usage: options line' +
                          'to make it more obvious that a usage error has occurred')
                detail = detail[_.start():]
        detail = detail.rstrip('\n')
        detail = re.sub(r'\r', '', detail)
        detail = re.sub(r'\n', r' \\n ', detail)
        detail = re.sub(r',\s*', '... ', detail)
        self.detail = detail

    def cmd(self, cmdline):
        log.info("cmd: %s", cmdline)
        shell = self.get_opt('shell')
        try:
            proc = None
            if shell:
                proc = subprocess.Popen(cmdline, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, shell=True)
            else:
                proc = subprocess.Popen(cmdline.split(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            (stdout, stderr) = proc.communicate()
            log.debug("stdout: %s", stdout)
            log.debug("stderr: %s", stderr)
            returncode = proc.wait()
            log.debug("returncode: %s", returncode)
            if returncode > 255:
                log.debug("mod 256")
                returncode = int(returncode % 256)
            if shell and returncode == 127:
                #if returncode != ERRORS['UNKNOWN'] and re.match('^/bin/[a-z]{0,2}sh: .*: command not found', stdout):
                log.debug('detected \'command not found\' when using shell ' +
                          'with not UNKNOWN exit code, resetting to UNKNOWN')
                returncode = ERRORS['UNKNOWN']
            if returncode in self.returncodes:
                log.debug("translating exit code '%s' => '%s'", returncode, self.returncodes[returncode])
                self.status = self.returncodes[returncode]
            else:
                log.info("non-standard exit code detected, resetting to CRITICAL")
                self.status = "CRITICAL"
            self.detail = stdout
        except subprocess.CalledProcessError as _:
            log.info("subprocess.CalledProcessError, resetting to UNKNOWN")
            self.status = "UNKNOWN"
            self.detail = str(_)
        except OSError as _:
            log.info("OSError, resetting to UNKNOWN")
            self.status = "UNKNOWN"
            self.detail = "OSError: '{0}' when running '{1}'".format(_, cmdline)
        if not self.detail:
            self.detail = '<no output>'
        log.debug("raw detail: %s", self.detail)

    def process_perfdata(self):
        perfdata_raw = None
        if '|' in self.detail:
            self.detail, perfdata_raw = self.detail.split('|', 1)
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
                        self.headers += [header.upper()]
                        self.perfdata += [val]
                    else:
                        log.warn("no valid numeric value to extract found in perfdata item '%s'", item)
                else:
                    log.warn("no key=value format detected in item '%s'", item)
        self.detail = self.detail.strip()

    def output(self):
        output = "{status},{detail}".format(status=self.status, detail=self.detail)
        for val in self.perfdata:
            output += ',' + val
        print(','.join(self.headers))
        print(output)


if __name__ == '__main__':
    GeneosWrapper().main()
    # Must always exit zero for Geneos otherwise it won't take the output and will show as raw error
    sys.exit(0)
