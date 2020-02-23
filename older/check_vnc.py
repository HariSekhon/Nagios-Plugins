#!/usr/bin/env python
#
#  Author: Hari Sekhon
#  Date: 2008-02-28 14:49:50 +0000 (Thu, 28 Feb 2008)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

"""Nagios plugin to test the status of VNC on a remote machine. Requires
   the "vncsnapshot" program to be installed somewhere in the path"""

from __future__ import print_function

import os
import sys
import time
from optparse import OptionParser
import lib_nagios as nagios
from lib_nagios import NagiosTester, which, end
from lib_nagios import OK, WARNING, CRITICAL, UNKNOWN, DEFAULT_TIMEOUT

__author__      = "Hari Sekhon"
__title__       = "Nagios Plugin for VNC"
__version__     = '0.7.0'

nagios.CHECK_NAME = "VNC"
# The standard VNC port
DEFAULT_PORT      = 5900


class VncTester(NagiosTester):
    """Holds state for the vnc test"""

    def __init__(self):
        """Initializes all variables to their default states"""

        super(VncTester, self).__init__()

        #self.port       = ""
        self.passwdfile = ""


    def validate_variables(self):
        """Runs through the validation of all test variables
        Should be called before the main test to perform a sanity check
        on the environment and settings"""

        self.validate_host()
        #self.validate_port()
        self.validate_passwdfile()
        self.validate_timeout()


#    def validate_port(self):
#        """Exits with an error if the port is not valid"""
#
#        if not self.port:
#            self.port = ""
#        else:
#            try:
#                self.port = int(self.port)
#                if not 1 <= self.port <= 65535:
#                    raise ValueError
#            except ValueError:
#                end(UNKNOWN, "port number must be a whole number between " \
#                           + "1 and 65535")


    def validate_passwdfile(self):
        """Exits with an error if the passwd file is not given
        or if the file is non-existent or cannot be accessed for any reason"""

        if not self.passwdfile:
            end(UNKNOWN, "You must supply a passwd file containing " \
                       + "the VNC password in order to connect. See --help " \
                       + "for details")

        if not os.path.exists(self.passwdfile):
            end(UNKNOWN, "vnc passwd file '%s' does not exist" \
                                                        % self.passwdfile)

        if not os.path.isfile(self.passwdfile):
            end(UNKNOWN, "'%s' is not a file, " \
                       + "cannot be used as the vnc passwd file")

        if not os.access(self.passwdfile, os.R_OK):
            end(UNKNOWN, "vnc passwd file '%s' is not " % self.passwdfile \
                       + "readable, please allow read permission on this file")


    def test_vnc(self):
        """Performs the test of the vnc server"""

        self.validate_variables()
        self.set_timeout()

        self.vprint(2, "now running vnc test")

        cmd = "%s -compresslevel 0 -passwd %s -vncQuality 0 %s /dev/null" \
              % (which("vncsnapshot"), self.passwdfile, self.server)

        result, output = self.run(cmd)

        if result == 0:
            if not output:
                return (WARNING, "Test passed but no output was received " \
                               + "from vncsnapshot program, abnormal "     \
                               + "condition, please check.")
            else:
                msg = "vnc logged in and image obtained successfully"
                if self.verbosity >= 1:
                    line1 = output.split("\n")[0]
                    if line1[:36] == "VNC server supports protocol version":
                        msg += ". %s" % line1
                    return (OK, msg)
                else:
                    return (OK, msg)
        else:
            if not output:
                return (CRITICAL, "Connection failed. " \
                                + "There was no output from vncsnapshot")
            else:
                if output.split("\n")[0][:36] == \
                                        "VNC server supports protocol version":
                    output = "".join(output.split("\n")[1:])
                if "Connection refused" in output and self.verbosity == 0:
                    output = "Connection refused"
                return (CRITICAL, "Error connecting to vnc server - %s" \
                                        % output.replace("\n", " ").rstrip(" "))


def main():
    """Parses args and calls func to test vnc server"""

    tester = VncTester()
    parser = OptionParser()
    parser.add_option( "-H",
                       "--server",
                       dest="server",
                       help="The Hostname or IP Address of the VNC " \
                          + "server")

# vncsnapshot doesn't support ports yet
#    parser.add_option( "-p",
#                       "--port",
#                       dest="port",
#                       help="The port on the server to test. Defaults to %s" \
#                                                                % DEFAULT_PORT)

    parser.add_option( "-f",
                       "--passwd-file",
                       dest="passwdfile",
                       help="The VNC password file to use. You can generate " \
                          + "this using 'vncpasswd <filename>' on the "       \
                          + "command line")

    parser.add_option( "-l",
                       "--label",
                       dest="service",
                       help="Change result prefix (Defaults to \"%s\")"
                                                  % nagios.CHECK_NAME)

    parser.add_option( "-t",
                       "--timeout",
                       dest="timeout",
                       help="Sets a timeout after which the the plugin will"   \
                          + " self terminate. Defaults to %s seconds."         \
                                                              % DEFAULT_TIMEOUT)

    parser.add_option( "-T",
                       "--timing",
                       action="store_true",
                       dest="timing",
                       help="Enable timer output")

    parser.add_option(  "-v",
                        "--verbose",
                        action="count",
                        dest="verbosity",
                        help="Verbose mode. Good for testing plugin. By "     \
                           + "default only one result line is printed as per" \
                           + " Nagios standards")

    parser.add_option( "-V",
                        "--version",
                        action = "store_true",
                        dest = "version",
                        help = "Print version number and exit" )

    (options, args) = parser.parse_args()

    if args:
        parser.print_help()
        sys.exit(UNKNOWN)

    if options.version:
        print(("%s version %s" % (__title__, __version__)))
        sys.exit(UNKNOWN)

    tester.passwdfile = options.passwdfile
    #tester.port       = options.port
    tester.server     = options.server
    tester.timeout    = options.timeout
    tester.verbosity  = options.verbosity

    if options.service != None:
        nagios.CHECK_NAME = options.service

    if options.timing:
        start_time = time.time()

    returncode, output = tester.test_vnc()

    if options.timing:
        finish_time = time.time()
        total_time = finish_time - start_time

        output += ". Test completed in %.3f seconds" % total_time

    end(returncode, output)
    sys.exit(UNKNOWN)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Caught Control-C...")
        sys.exit(CRITICAL)
