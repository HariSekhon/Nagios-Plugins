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

CSV Adapter program to convert any Nagios Plugin results to CSV format

Usage:

Put 'adapter_csv.py' at the front of any nagios plugin command line and it will call the plugin and translate the
output for you to CSV format with STATUS, MESSAGE and optionally additional PERF1 ... PERFN columns for each perfdata
metric present.

Alternatively you can feed it literal output from a nagios plugin combined with the --result <exitcode> switch.

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
__version__ = '0.6.3'


class AdapterCSV(CLI):

    def __init__(self):
        # Python 2.x
        super(AdapterCSV, self).__init__()
        # Python 3.x
        # super().__init__()
        # special case to make all following args belong to the passed in command and not to this program
        self._CLI__parser.disable_interspersed_args()
        self._CLI__parser.set_usage('{prog} [options] <nagios_plugin> <plugin_args> ...'.format(prog=prog))
        self.timeout_default = 60
        log.setLevel(logging.ERROR)
        self.returncodes = {}
        for key in ERRORS:
            self.returncodes[ERRORS[key]] = key
        self.perfdata_regex = re.compile(r'(\d+(?:\.\d+)?)([A-Za-z]{1,2}|%)?')
        self._status = 'UNKNOWN'
        self.message = '<None>'
        self.perfdata = []
        self.headers = ['STATUS', 'MESSAGE']
        self.separator = ','

    # @Overrride to prevent injecting the usual default opts
    # update: allowing default opts now as it's handy to have multiple verbosity levels for debugging
    #def add_default_opts(self):
    #    pass

    def add_options(self):
        self.add_opt('-s', '--shell', action='store_true',
                     help='Use Shell to execute nagios plugin command args (default: false)')
        self.add_opt('-r', '--result', metavar='<exitcode>',
                     help='Specify exitcode and use args as Nagios Plugin data results ' \
                        + 'rather than nagios plugin command to execute')
        # Don't provide this to subclasses AdapterGeneos
        if type(self).__name__ == 'AdapterCSV':
            self.add_opt('--no-header', action='store_true', help='Do not output CSV header')

    def run(self):
        argstr = ' '.join(self.args)
        if not argstr:
            self.usage('missing required args for either nagios plugin command to execute or result data')
        result = self.get_opt('result')
        if result is not None:
            self.status = result
            self.message = argstr
        else:
            self.cmd(argstr)
        self.process_message()
        self.process_perfdata()
        self.output()

    #@staticmethod
    def process_message(self):
        message = self.message
        message = re.sub(r'\s*(?:[\w\s]+?\s)?(?:OK|WARNING|CRITICAL|UNKNOWN)(?:\s[\w\s]+?)?\s*:\s*',
                         '', message, 1, re.I)
        if re.search('^Hari Sekhon', message):
            _ = re.search('^usage:', message, re.M)
            if _:
                log.debug('stripping off my extended plugin description header up to usage: options line' +
                          'to make it more obvious that a usage error has occurred')
                message = message[_.start():]
        message = message.rstrip('\n')
        message = re.sub(r'\r', '', message)
        message = re.sub(r'\n', r' \\n ', message)
        message = re.sub(r',\s*', '... ', message)
        self.message = message

    @property
    def status(self):
        return self._status

    @status.setter
    def status(self, returncode):
        try:
            returncode = int(returncode)
        except ValueError:
            log.info("returncode '%s' failed to convert to int", returncode)
        if returncode in self.returncodes:
            log.debug("translating exit code '%s' => '%s'", returncode, self.returncodes[returncode])
            self._status = self.returncodes[returncode]
        elif returncode in ERRORS:
            self._status = returncode
        else:
            log.info("non-standard exit code detected, resetting to UNKNOWN")
            # this is a property that can handle either type not a real variable
            self._status = 'UNKNOWN'

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
            if isinstance(stdout, bytes):
                stdout = str(stdout.decode('utf-8'))
            if isinstance(stderr, bytes):
                stderr = str(stderr.decode('utf-8'))
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
            self.status = returncode
            self.message = stdout
        except subprocess.CalledProcessError as _:
            log.info("subprocess.CalledProcessError, resetting to UNKNOWN")
            # this is a property that can handle either type not a real variable
            self.status = "UNKNOWN"
            self.message = str(_)
        except OSError as _:
            log.info("OSError, resetting to UNKNOWN")
            self.status = "UNKNOWN"
            self.message = "OSError: '{0}' when running '{1}'".format(_, cmdline)
        if not self.message:
            self.message = '<no output>'
        log.debug("raw detail: %s", self.message)

    def process_perfdata(self):
        perfdata_raw = None
        if '|' in self.message:
            self.message, perfdata_raw = self.message.split('|', 1)
        if perfdata_raw:
            log.debug("raw perfdata: %s", perfdata_raw)
            for item in perfdata_raw.split():
                if '=' in item:
                    header, data = item.split('=', 1)
                    data = data.split(';')[0]
                    match = self.perfdata_regex.search(data)
                    if match:
                        val = match.group(1)
                        log.debug("found numeric value '%s' in item '%s'", val, item)
                        if match.group(2):
                            units = match.group(2)
                            log.debug("found units '%s' in item '%s'", units, item)
                            header += " ({0})".format(units)
                        header = header.strip('"')
                        header = header.strip("'")
                        header = header.replace(self.separator, '_')
                        self.headers += [header.upper()]
                        self.perfdata += [val]
                    else:
                        log.warn("no valid numeric value to extract found in perfdata item '%s'", item)
                else:
                    log.warn("no key=value format detected in item '%s'", item)
        self.message = self.message.strip()

    def output(self):
        output = "{status},{message}".format(status=self.status, message=self.message)
        for val in self.perfdata:
            output += self.separator + val
        if not self.get_opt('no_header'):
            print(self.separator.join(self.headers))
        print(output)


if __name__ == '__main__':
    AdapterCSV().main()
