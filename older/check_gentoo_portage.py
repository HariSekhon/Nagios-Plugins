#!/usr/bin/env python
#
#  Author: Hari Sekhon
#  Date: 2008-02-19 16:46:44 +0000 (Tue, 19 Feb 2008)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

"""

Nagios Plugin to check Portage on Gentoo Linux. Checks the Portage tree is up to date, that there are no security
package alerts and optionally whether there are any non-security package updates available

"""

from __future__ import print_function

import os
import re
import sys
import signal
import time
# pylint: disable=wrong-import-position
try:
    from subprocess import Popen, PIPE, STDOUT
except ImportError:
    print("Failed to import subprocess module.", end=' ')
    print("Perhaps you are using a version of python older than 2.4?")
    sys.exit(4)
from optparse import OptionParser

__author__ = "Hari Sekhon"
__title__ = "Nagios Plugin for Gentoo Portage"
__version__ = "0.9.1"

# Standard Nagios return codes
OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

# The utilities that we need. These are the same on every standard Gentoo system
# If you are doing something non-standard, you may need to edit these paths.
GLSACHECK = "/usr/bin/glsa-check"
EMERGE = "/usr/bin/emerge"

# Going direct now, Originally used an emerge call but it was sloooow.
# This is much faster and allows for portage version differences when
# determining the last synced time, as emerge --info doesn't give this
# in the older versions
TIMESTAMP_LOCATIONS = (
    "/usr/portage/metadata/timestamp.chk",
    "/var/cache/edb/dep/timestamp.chk"
)

DEFAULT_PORTAGE_TREE_AGE = 25.0 # hours
DEFAULT_TIMEOUT = 20 # seconds

def end(status, message):
    """Exits the plugin with first arg as the return code and the second
    arg as the message to output"""

    check = "Portage "
    if status == OK:
        print("%sOK: %s" % (check, message))
        sys.exit(OK)
    elif status == WARNING:
        print("%sWARNING: %s" % (check, message))
        sys.exit(WARNING)
    elif status == CRITICAL:
        print("%sCRITICAL: %s" % (check, message))
        sys.exit(CRITICAL)
    else:
        print("UNKNOWN: %s" % message)
        sys.exit(UNKNOWN)


for _ in GLSACHECK, EMERGE:
    if not os.path.exists(_):
        if not os.path.exists('/etc/gentoo-release'):
            end(UNKNOWN, "Utility '%s' cannot be found and system does " % _ \
                       + "not appear to be Gentoo")
        elif _ == GLSACHECK:
            end(UNKNOWN, "Utility '%s' cannot be found. " % _ \
                       + "You may need to 'emerge gentoolkit' first")
        else:
            end(UNKNOWN, "Utility '%s' cannot be found, cannot run check" % _)

    if not os.access(_, os.X_OK):
        end(UNKNOWN, "Utility '%s' is not set executable, cannot run check" \
                                                                          % _)


class PortageTester(object):
    """Class to hold all portage test functions and state"""

    def __init__(self):
        """Initialize all object variables"""

        self.all_updates = False
        self.dependencies = False
        self.glsa_ids = []
        self.max_portage_tree_age = DEFAULT_PORTAGE_TREE_AGE
        self.newuse = False
        self.no_warn_applied = False
        self.timeout = DEFAULT_TIMEOUT
        self.verbosity = 0
        self.warn_any_package = False

    def validate_all_variables(self):
        """Validates all object variables to make sure the
        environment is sane"""

        self.validate_exclusions()
        self.validate_portage_tree_age()
        self.validate_timeout()
        self.validate_verbosity()
        if self.warn_any_package:
            self.all_updates = True

    def validate_exclusions(self):
        """Validates that given exclusions are in the correct format"""

        if self.glsa_ids != None:
            self.glsa_ids = [exclusion.strip() for exclusion in str(self.glsa_ids).split(",")]
            re_glsa = re.compile(r'^\d{6}-\d{2}$')
            for exclusion in self.glsa_ids:
                glsa_invalid_msg = "GLSA exclusion '%s' is " % exclusion \
                            + "not a valid GLSA id. See --help for details"
                if not re_glsa.match(exclusion):
                    end(UNKNOWN, glsa_invalid_msg)
                if int(exclusion[4:6]) < 1 or int(exclusion[4:6]) > 12:
                    end(UNKNOWN, glsa_invalid_msg)
                if int(exclusion[-2:]) == 0:
                    end(UNKNOWN, glsa_invalid_msg)
                if int(exclusion[:6]) > int(time.strftime("%Y%m")):
                    end(UNKNOWN, \
                        "GLSA id '%s' is in the future and " % exclusion \
                      + "therefore cannot be valid (or system clock is wrong)")
                # 200310-03 was the first ever GLSA id
                if exclusion < "200310-03":
                    end(UNKNOWN, "GLSA id '%s' predates the " % exclusion      \
                               + "first ever GLSA issued. Please correct "     \
                               + "the GLSA id exclusions you have provided. "  \
                               + "See --help for more details")
            self.glsa_ids = list(set(self.glsa_ids))
            self.glsa_ids.sort()
            if self.verbosity >= 3:
                exclusion_ids = ""
                for exclusion in self.glsa_ids:
                    exclusion_ids += "%s " % exclusion
                print("GLSA ids excluded: %s" % exclusion_ids)

    def validate_portage_tree_age(self):
        """Validates that given portage tree age variable"""

        if self.max_portage_tree_age is None:
            self.max_portage_tree_age = DEFAULT_PORTAGE_TREE_AGE
        try:
            self.max_portage_tree_age = float(self.max_portage_tree_age)
        except ValueError:
            end(UNKNOWN, "Max portage tree age must be specified as a number " \
                       + "representing hours, decimals accepted")

        if self.max_portage_tree_age < 0.1 or self.max_portage_tree_age > 744:
            end(UNKNOWN, "Max portage tree age must be between " \
                       + "0.1 and 744 hours")

    def validate_timeout(self):
        """Validates the timeout"""

        if self.timeout is None:
            self.timeout = DEFAULT_TIMEOUT
        try:
            self.timeout = int(self.timeout)
        except ValueError:
            end(UNKNOWN, "Timeout must be an whole number, " \
                       + "representing the timeout in seconds")
        if self.timeout < 1 or self.timeout > 3600:
            end(UNKNOWN, "Timeout must be a number between 1 and 3600 seconds")

    def validate_verbosity(self):
        """Validates the verbosity"""

        if self.verbosity is None:
            self.verbosity = 0
        try:
            self.verbosity = int(self.verbosity)
            if self.verbosity < 0:
                raise ValueError
        except ValueError:
            end(CRITICAL, "Invalid verbosity type, must be positive numeric " \
                        + "integer")

    def run(self, cmd):
        """runs a system command and returns a tuple containing
        the return code and an array of lines of the output"""

        if not cmd:
            end(UNKNOWN, "Internal python error - " \
                       + "no cmd supplied for run function")
        self.vprint(3, "running command: %s" % cmd)
        try:
            process = Popen(cmd.split(), stdin=PIPE, stdout=PIPE, stderr=STDOUT)
        except OSError as error:
            error = str(error)
            if error == "No such file or directory":
                end(UNKNOWN, "Cannot find utility '%s'" % cmd.split()[0])
            else:
                end(UNKNOWN, "Error trying to run utility '%s' - %s" \
                                                      % (cmd.split()[0], error))
        stdout, stderr = process.communicate()
        if stdout is None or stdout == "":
            end(UNKNOWN, "No output from utility '%s'" % cmd.split()[0])
        returncode = process.returncode
        if returncode != 0:
            stderr = str(stdout).replace("\n", " ")
            end(UNKNOWN, "'%s' utility returned an exit code of '%s' - '%s'" \
                                 % (cmd.split()[0], process.returncode, stderr))
        else:
            self.vprint(3, "Returncode: '%s'\nOutput: '%s'" % (returncode, stdout))
            return (returncode, str(stdout.decode()).split("\n"))

    def set_timeout(self):
        """sets an alarm to time out the test"""

        if self.timeout == 1:
            self.vprint(3, "setting plugin timeout to %s second" \
                                                                % self.timeout)
        else:
            self.vprint(3, "setting plugin timeout to %s seconds"\
                                                                % self.timeout)
        signal.signal(signal.SIGALRM, self.sighandler)
        signal.alarm(self.timeout)

    def sighandler(self, _discarded, _discarded2):
        """Function to be called by signal.alarm to kill the plugin"""

        end(CRITICAL, "Gentoo portage plugin has self terminated after " \
                    + "exceeding the timeout (%s seconds)" % self.timeout)

    def get_portage_timestamp(self):
        """Gets the latest portage timestamp from portage touchfiles
        The list of files is maintained newest to oldest,
        and the first one found is used"""

        timestamp = ""
        file_read = False
        timestamp_file = ""
        timestamp_file_mod_date = 0

        for touchfile in TIMESTAMP_LOCATIONS:
            if not os.path.exists(touchfile):
                continue
            elif not os.access(touchfile, os.R_OK):
                end(CRITICAL, "Error - cannot read latest portage timestamp " \
                  + "due to restrictive permissions on file '%s'" % touchfile)
            touchfile_mod_date = os.stat(touchfile)[8]
            if touchfile_mod_date > timestamp_file_mod_date:
                timestamp_file_mod_date = touchfile_mod_date
                timestamp_file = touchfile

        if timestamp_file == "":
            end(CRITICAL, "Error - no portage timestamp file could be found, " \
                        + "please update to latest version of this plugin "    \
                        + "and portage ('emerge portage'). If problem "        \
                        + "persists, contact the author")

        self.vprint(3, "using portage timestamp file '%s'" % timestamp_file)

        try:
            timestamp_fh = open(timestamp_file)
            timestamp = timestamp_fh.readline().strip()
            timestamp_fh.close()
            file_read = True
        except IOError as io_error:
            end(CRITICAL, "Error reading timestamp information, cannot " \
                      + "verify Portage is current. Error - %s" % io_error)
        if not file_read:
            end(CRITICAL, "Error reading timestamp file, portage may have " \
                + "changed. Try running in debug mode -vvv or contact the " \
                + "author")
        return timestamp

    def test_portage_current(self):
        """Tests that the portage tree is current as the
        security announcements depend on this"""

        self.vprint(2, "testing if portage is current")
        timestamp = self.get_portage_timestamp()
        self.vprint(3, "timestamp of portage tree: '%s'" % timestamp)
        if timestamp == "":
            end(UNKNOWN, "Cannot determine timestamp of last portage sync. " \
                       + "There is no guarantee that security package info " \
                       + "will be current")
        try:
            portage_tree_time = time.strptime(timestamp, \
                                                  "%a, %d %b %Y %H:%M:%S +0000")
        except ValueError:
            end(UNKNOWN, "Error converting portage timestamp from '%s'. " \
                                                                   % timestamp \
                       + "It is likely the format has changed and the plugin " \
                       + "needs to be updated to reflect this, please "        \
                       + "contact author")
        try:
            now = time.strptime(time.strftime("%a, %d %b %Y %H:%M:%S +0000", \
                              time.gmtime()), "%a, %d %b %Y %H:%M:%S +0000")
        except ValueError:
            end(UNKNOWN, "Internal python error converting current time to " \
                       + "the right format, please contact author")
        try:
            portage_tree_time = time.mktime(portage_tree_time)
        except (ValueError, OverflowError):
            end(UNKNOWN, "Plugin internal time conversion error on portage " \
                       + "tree time, please contact author")
        try:
            now = time.mktime(now)
        except (ValueError, OverflowError):
            end(UNKNOWN, "Plugin internal time conversion error on local " \
                       + "time, please contact author")
        portage_age = (now - portage_tree_time)/3600.0
        self.vprint(2, "portage tree is %.1f hours old" % portage_age)
        if portage_age > self.max_portage_tree_age:
            end(CRITICAL, "Portage tree is %.1f hours out of date, " \
                                                                   % portage_age \
                        + "security package information is not reliable")
        elif portage_age < 0:
            end(WARNING, "Portage tree timestamp is in the future! (%s)" \
                                                                    % timestamp)
        return portage_age

    def get_all_updates(self):
        """Checks if any package has an available update
        Not recommended as this will often return in an alert
        Returns a tuple like (True/False, "string information on packages")"""

        self.vprint(2, "checking for any package updates")

        cmd = "%s --update --pretend --verbose --color n world" % EMERGE
        if self.dependencies:
            cmd += " --deep"
        if self.newuse:
            cmd += " --newuse"
        returncode, output = self.run(cmd)
        if returncode != 0:
            end(UNKNOWN, "Error running '%s', exit code: %s output: %s" \
                                                 % (EMERGE, returncode, output))
        package_changes_available = False
        re_upgrade_info = re.compile(r'\d+ packages{0,1} \(.+\)')
        upgrade_info = ""
        for line in output:
            if line[:7] == "Total: ":
                match_object = re_upgrade_info.search(line)
                if match_object:
                    upgrade_info = match_object.group()
                elif line[:17] == "Total: 0 packages":
                    upgrade_info = "0 packages to upgrade"
                break
        if upgrade_info == "":
            end(CRITICAL, "No upgrade information could be parsed, portage " \
                        + "version may have changed or be too old. Try " \
                        + "upgrading both this plugin and portage ('emerge " \
                        + "portage'). If the problem persists, contact the " \
                        + "author")
        self.vprint(3, "packages upgrade info: %s" % upgrade_info)
        num_package_changes = upgrade_info.split("package")[0].strip()
        try:
            num_package_changes = int(num_package_changes)
        except ValueError:
            end(UNKNOWN, "Error parsing number of changed packages, possible " \
                       + "change in format of portage output. Please upgrade " \
                       + "this plugin and portage ('emerge portage'). If "     \
                       + "problem persists, contact the author")
        if num_package_changes >= 1:
            package_changes_available = True
        return (package_changes_available, upgrade_info)

    def get_security_status(self):
        """Calls get_security_updates to find any security updates, then
        calls process_security_updates in order to process the results
        Returns a tuple of the status code and the status message"""

        security_updates, applied_updates = self.get_security_updates()
        status, message = self.process_security_updates(security_updates, \
                                                                applied_updates)
        return status, message

    def get_security_updates(self):
        """Checks if any package has a security update
        Returns a tuple of status code and message"""

        self.vprint(2, "checking for any security updates")
        cmd = "%s --nocolor --list affected" % GLSACHECK
        returncode, output = self.run(cmd)
        if returncode != 0:
            end(UNKNOWN, "Error running '%s', exit code: %s output: %s" \
                                                 % (EMERGE, returncode, output))
        re_security_package_line = re.compile(r'^.{1,12}\s\[N\]\s')
        re_applied_package_line = re.compile(r'^.{1,12}\s\[A\]\s')
        security_updates = []
        applied_updates = []
        for line in output:
            if re_security_package_line.match(line):
                security_updates.append(line)
        for line in output:
            if re_applied_package_line.match(line):
                applied_updates.append(line)
        if len(output) > 5 + len(security_updates) + len(applied_updates):
            end(WARNING, "GLSA output signature does not match current known " \
                       + "format, please make sure you have upgraded to the "  \
                       + "latest versions of both this plugin and gentoolkit " \
                       + "('emerge gentoolkit'). If the problem persists, "    \
                       + "please contact the author for a fix")
        return security_updates, applied_updates

    def process_security_updates(self, security_updates, applied_updates):
        """Takes 2 arrays of security updates and applied updates and
        returns a tuple of the status and output for the test"""

        if isinstance(self.glsa_ids, list):
            for exclusion in self.glsa_ids:
                for index in range(0, len(security_updates)):
                    if security_updates[index].split()[0].strip() == exclusion:
                        self.vprint(3, "excluding GLSA id: %s" % exclusion)
                        security_updates.pop(index)
                        break
                for index in range(0, len(applied_updates)):
                    if applied_updates[index].split()[0].strip() == exclusion:
                        self.vprint(3, "excluding GLSA id: %s" % exclusion)
                        applied_updates.pop(index)
                        break
        num_security_updates = len(security_updates)
        num_applied_updates = len(applied_updates)
        status, message = \
                self.process_security_package_output(num_security_updates, \
                                                     num_applied_updates)
        return status, message

    def process_security_package_output(self, num_security_updates, \
                                                          num_applied_updates):
        """Forms output based on the number of security and applied packages"""

        if num_security_updates == 0:
            status = OK
            message = "0 Security Updates Available"
        else:
            status = CRITICAL
        if num_security_updates == 1:
            message = "1 Security Update Available"
        elif num_security_updates > 1:
            message = "%s Security Updates Available" % num_security_updates
        if self.no_warn_applied != True and num_applied_updates != 0:
            if status != CRITICAL:
                status = WARNING
        if num_applied_updates == 1:
            message += ". 1 Security Update marked as already applied"
        elif num_applied_updates > 1:
            message += ". %s Security " % num_applied_updates \
                     + "Updates marked as already applied"
        return status, message

    def test_for_updates(self):
        """Starts tests"""

        #status = UNKNOWN
        message = ""
        self.validate_all_variables()
        self.set_timeout()
        portage_age = self.test_portage_current()
        status, message = self.get_security_status()
        if self.all_updates:
            package_updates_available, upgrade_info = self.get_all_updates()
            if package_updates_available:
                if self.warn_any_package and status == OK:
                    status = WARNING
                message += ". Package Changes Available: "
                if self.verbosity >= 1:
                    message += "%s" % upgrade_info
                else:
                    message += "%s" % upgrade_info.split("(")[0]
            else:
                message += ". No General Package Updates Available"
        if self.verbosity >= 1:
            message += ". Portage last synchronized %.1f hours ago" \
                                                                % portage_age
        return status, message

    def vprint(self, threshold, message):
        """Prints a message if the first arg is numerically greater than the
        verbosity level"""
        if self.verbosity >= threshold:
            print("%s" % message)

def main():
    """Parses command line options and calls the test function"""

    tester = PortageTester()
    parser = OptionParser()
    parser.add_option("-a",
                      "--all-updates",
                      action="store_true",
                      dest="all_updates",
                      help="Shows if any packages changes are available. "    \
                         + "Significantly slows down the test, you should "   \
                         + "increase the timeout if using this feature. "     \
                         + "Does not change state by default, must use "      \
                         + "--warn-on-any-update in order to "                \
                         + "return a warning state if there are any "         \
                         + "non-security package updates available")

    parser.add_option("--warn-on-any-update",
                      action="store_true",
                      dest="warn_any_package",
                      help="Warns if there are any (non-security) package "   \
                         + "upgrades available. Not Recommended. Requested "  \
                         + "feature, but Gentoo updates too fast for this "   \
                         + "to be practical, you may end up having a lot of " \
                         + "warning alerts unless you upgrade daily. "        \
                         + "Implies --any-update")

    parser.add_option("--exclude",
                      dest="glsa_ids",
                      help="GLSAs to ignore. Format must be the same as "     \
                         + "the official GLSA ids (You can see these "        \
                         + "numbers by using -vvv for full debug output). "   \
                         + "Can take a comma separated list of GLSA ids to "  \
                         + "exclude several alerts")

    parser.add_option("-D",
                      "--dependencies",
                      action="store_true",
                      dest="dependencies",
                      help="Includes all dependencies when looking for any "  \
                         + "packages that can upgrade. Only valid when used " \
                         + "with --any-update")

    parser.add_option("-N",
                      "--newuse",
                      action="store_true",
                      dest="newuse",
                      help="Includes packages that need recompiling due to " \
                         + "changed USE flags. Only valid when used with "   \
                         + "--any-update")

    parser.add_option("-T",
                      "--portage-tree-age",
                      dest="hours",
                      help="Maximum time since the last portage sync. "       \
                         + "Gentoo package alerts rely on the portage tree "  \
                         + "being current. If portage has not been updated "  \
                         + "in this many hours then a Warning alert is "      \
                         + "raised. You can set this in hours, decimals are " \
                         + "accepted. Must not be below 0.1 hours "           \
                         + "(6 minutes) or above 744.0 hours (31 days). "     \
                         + "Default is %s hours."                             \
                         % DEFAULT_PORTAGE_TREE_AGE)

    parser.add_option("--no-warn-applied",
                      action="store_true",
                      dest="no_warn_applied",
                      help="Disables warnings for current security updates "  \
                         + "that are marked as having been already applied. " \
                         + "Not Recommended. Requested feature to "           \
                         + "ignore packages that have been manually marked "  \
                         + "as applied which still show up in the current "   \
                         + "security vulnerabilities list. Do not enable "    \
                         + "this unless you know what you are doing. This "   \
                         + "is not referring to old security updates which "  \
                         + "are ignored anyway, this refers to current "      \
                         + "security updates that have the status applied "   \
                         + "but that still show as needing fixing. These "    \
                         + "packages are usually still on the current "       \
                         + "vulnerabilities list for a good reason, "         \
                         + "ignoring them may reduce the security of your "   \
                         + "system.")

    parser.add_option("-t",
                      "--timeout",
                      dest="timeout",
                      help="Sets a timeout in seconds after which the " \
                          +"plugin will exit (defaults to %s seconds). " \
                                                     % DEFAULT_TIMEOUT)

    parser.add_option("-v",
                      "--verbose",
                      action="count",
                      dest="verbosity",
                      help="Verbose mode. Use once for more information or " \
                         + "multiple times for debugging. By default only "  \
                         + "one result line is printed as per Nagios "       \
                         + "standards")

    parser.add_option("-V",
                      "--version",
                      action="store_true",
                      dest="version",
                      help="Print version number and exit")

    (options, args) = parser.parse_args()

    if args:
        parser.print_help()
        sys.exit(UNKNOWN)

    tester.all_updates = options.all_updates
    tester.dependencies = options.dependencies
    tester.glsa_ids = options.glsa_ids
    tester.max_portage_tree_age = options.hours
    tester.newuse = options.newuse
    tester.no_warn_applied = options.no_warn_applied
    tester.timeout = options.timeout
    tester.verbosity = options.verbosity
    tester.warn_any_package = options.warn_any_package

    if options.version:
        print("%s Version %s" % (__title__, __version__))
        sys.exit(OK)

    result, output = tester.test_for_updates()
    end(result, output)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Caught Control-C...")
        sys.exit(CRITICAL)
