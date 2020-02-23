#!/usr/bin/env python
#
#  Author: Hari Sekhon
#  Date: 2008-02-28 14:49:50 +0000 (Thu, 28 Feb 2008)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

"""Nagios plugin to test the status of a Subversion (SVN) server. Requires
   the subversion client "svn" to be installed somewhere in the path"""

from __future__ import print_function

import sys
import time
from optparse import OptionParser
import lib_nagios as nagios
from lib_nagios import NagiosTester, which, end
from lib_nagios import OK, WARNING, CRITICAL, UNKNOWN, DEFAULT_TIMEOUT

__author__      = "Hari Sekhon"
__title__       = "Nagios Plugin for Subversion"
__version__     = '0.7.0'

nagios.CHECK_NAME = "SVN"


class SvnTester(NagiosTester):
    """Holds state for the svn test"""

    def __init__(self):
        """Initializes all variables to their default states"""

        super(SvnTester, self).__init__()

        self.directory  = ""
        self.http       = False
        self.https      = False
        self.password   = ""
        self.port       = ""
        self.protocol   = "svn"
        self.username   = ""


    def validate_variables(self):
        """Runs through the validation of all test variables
        Should be called before the main test to perform a sanity check
        on the environment and settings"""

        self.validate_host()
        self.validate_protocol()
        self.validate_port()
        self.validate_timeout()


    def validate_protocol(self):
        """Determines the protocol to use and sets it in the object"""

        if self.http and self.https:
            end(UNKNOWN, "cannot choose both http and https, they are " \
                       + "mutually exclusive")
        elif self.http:
            self.protocol = "http"
        elif self.https:
            self.protocol = "https"
        else:
            self.protocol = "svn"


    def validate_port(self):
        """Exits with an error if the port is not valid"""

        if self.port is None:
            self.port = ""
        else:
            try:
                self.port = int(self.port)
                if not 1 <= self.port <= 65535:
                    raise ValueError
            except ValueError:
                end(UNKNOWN, "port number must be a whole number between " \
                           + "1 and 65535")


    def generate_uri(self):
        """Creates the uri and returns it as a string"""

        if not self.port:
            port = ""
        else:
            port = ":" + str(self.port)

        if self.directory is None:
            directory = ""
        else:
            directory = "/" + str(self.directory).lstrip("/")

        uri = self.protocol + "://"  \
              + str(self.server)     \
              + str(port)            \
              + str(directory)

        return str(uri)


    def test_svn(self):
        """Performs the test of the subversion server"""

        self.validate_variables()
        self.set_timeout()

        self.vprint(2, "now running subversion test")

        uri = self.generate_uri()

        self.vprint(3, "subversion server address is '%s'" % uri)

        cmd = which("svn") + " ls " + uri + " --no-auth-cache --non-interactive"

        if self.username:
            cmd += " --username=%s" % self.username
        if self.password:
            cmd += " --password=%s" % self.password

        result, output = self.run(cmd)

        if result == 0:
            if not output:
                return (WARNING, "Test passed but no output was received " \
                               + "from svn program, abnormal condition, "  \
                               + "please check.")
            if self.verbosity >= 1:
                return (OK, "svn repository online - directory listing: " \
                          + "%s" % output.replace("\n", " ").strip())
            return (OK, "svn repository online - " \
                      + "directory listing successful")
        else:
            if not output:
                return (CRITICAL, "Connection failed. " \
                                + "There was no output from svn")
            if output == "svn: Can't get password\n":
                output = "password required to access this repository but" \
                       + " none was given or cached"
            output = output.lstrip("svn: ")
            return (CRITICAL, "Error connecting to svn server - %s " \
                                    % output.replace("\n", " ").rstrip(" "))


def main():
    """Parses args and calls func to test svn server"""

    tester = SvnTester()
    parser = OptionParser()
    parser.add_option( "-H",
                       "--server",
                       dest="server",
                       help="The Hostname or IP Address of the subversion "    \
                          + "server")

    parser.add_option( "-p",
                       "--port",
                       dest="port",
                       help="The port on the server to test if not using the " \
                          + "default port which is 3690 for svn://, 80 for "   \
                          + "http:// or 443 for https://.")

    parser.add_option( "--http",
                       action="store_true",
                       dest="http",
                       help="Connect to the server using the http:// " \
                          + "protocol (Default is svn://)")

    parser.add_option( "--https",
                       action="store_true",
                       dest="https",
                       help="Connect to the server using the https:// " \
                          + "protocol (Default is svn://)")

    parser.add_option( "-d",
                       "--dir",
                       "--directory",
                       dest="directory",
                       help="The directory on the host. Optional but usually " \
                          + "necessary if using http/https, eg if using an "   \
                          + "http WebDAV repository "                          \
                          + "http://somehost.domain.com/repos/svn so this "    \
                          + "would be --dir /repos/svn. Not usually needed "   \
                          + "for the default svn:// unless you want to test "  \
                          + "a specific directory in the repository")

    parser.add_option( "-U",
                       "--username",
                       dest="username",
                       help="The username to use to connect to the subversion" \
                          + " server.")

    parser.add_option( "-P",
                       "--password",
                       dest="password",
                       help="The password to use to connect to the subversion" \
                          + " server.")

    parser.add_option( "-l",
                       "--label",
                       dest="service",
                       help="Change result prefix (Defaults to \"%s\")"
                                                  % nagios.CHECK_NAME)

    parser.add_option( "-t",
                       "--timeout",
                       dest="timeout",
                       help="Sets a timeout after which the the plugin will"   \
                          + " self terminate. Defaults to %s seconds." \
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
        print("%s version %s" % (__title__, __version__))
        sys.exit(UNKNOWN)

    tester.directory  = options.directory
    tester.http       = options.http
    tester.https      = options.https
    tester.password   = options.password
    tester.port       = options.port
    tester.server     = options.server
    tester.timeout    = options.timeout
    tester.username   = options.username
    tester.verbosity  = options.verbosity

    if options.service != None:
        nagios.CHECK_NAME = options.service

    if options.timing:
        start_time = time.time()

    returncode, output = tester.test_svn()

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
