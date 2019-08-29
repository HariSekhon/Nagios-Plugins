#!/usr/bin/env python
#
#  Author: Hari Sekhon
#  Date: 2008-04-29 17:21:08 +0100 (Tue, 29 Apr 2008)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

"""
Nagios plugin to test for Yum updates on RedHat / CentOS Linux.

Can optionally alert on any available updates as well as just security related updates

See also: check_yum.pl (also part of the Advanced Nagios Plugins Collection)

Tested on CentOS 5 / 6 / 7
"""

import os
import re
import sys
import signal
OLD_PYTHON = False
# pylint: disable=wrong-import-position
try:
    from subprocess import Popen, PIPE, STDOUT
except ImportError:
    OLD_PYTHON = True
    import commands
from optparse import OptionParser

__author__ = "Hari Sekhon"
__title__ = "Nagios Plugin for Yum updates on RedHat/CentOS systems"
__version__ = "0.8.9"

# Standard Nagios return codes
OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

DEFAULT_TIMEOUT = 30

support_msg = "Please make sure you have upgraded to the latest version from " + \
              "https://github.com/harisekhon/nagios-plugins. If the problem persists, " + \
              "please raise a ticket at https://github.com/harisekhon/nagios-plugins/issues "+ \
              "with the full -vvv output"

def end(status, message):
    """Exits the plugin with first arg as the return code and the second
    arg as the message to output"""

    check = "YUM "
    if status == OK:
        print "%sOK: %s" % (check, message)
        sys.exit(OK)
    elif status == WARNING:
        print "%sWARNING: %s" % (check, message)
        sys.exit(WARNING)
    elif status == CRITICAL:
        print "%sCRITICAL: %s" % (check, message)
        sys.exit(CRITICAL)
    else:
        print "UNKNOWN: %s" % message
        sys.exit(UNKNOWN)

YUM = "/usr/bin/yum"

def check_yum_usable():
    """Checks that the YUM program and path are correct and usable - that
    the program exists and is executable, otherwise exits with error"""

    if not os.path.exists(YUM):
        end(UNKNOWN, "%s cannot be found" % YUM)
    elif not os.path.isfile(YUM):
        end(UNKNOWN, "%s is not a file" % YUM)
    elif not os.access(YUM, os.X_OK):
        end(UNKNOWN, "%s is not executable" % YUM)


class YumTester(object):
    """Class to hold all portage test functions and state"""

    def __init__(self):
        """Initialize all object variables"""

        self.all_updates = False
        self.no_cache_update = False
        self.no_warn_on_lock = False
        self.enable_repo = ""
        self.disable_repo = ""
        self.disable_plugin = ""
        self.yum_config = ""
        self.timeout = DEFAULT_TIMEOUT
        self.verbosity = 0
        self.warn_on_any_update = False

    def validate_all_variables(self):
        """Validates all object variables to make sure the
        environment is sane"""

        if self.timeout is None:
            self.timeout = DEFAULT_TIMEOUT
        try:
            self.timeout = int(self.timeout)
        except ValueError:
            end(UNKNOWN, "Timeout must be an whole number, " \
                       + "representing the timeout in seconds")

        if self.timeout < 1 or self.timeout > 3600:
            end(UNKNOWN, "Timeout must be a number between 1 and 3600 seconds")

        if self.verbosity is None:
            self.verbosity = 0
        try:
            self.verbosity = int(self.verbosity)
            if self.verbosity < 0:
                raise ValueError
        except ValueError:
            end(UNKNOWN, "Invalid verbosity type, must be positive numeric " \
                        + "integer")


    def run(self, cmd):
        """runs a system command and returns
        an array of lines of the output"""

        if not cmd:
            end(UNKNOWN, "Internal python error - " \
                       + "no cmd supplied for run function")

        if self.no_cache_update:
            cmd += " -C"

        if self.enable_repo:
            for repo in self.enable_repo.split(","):
                cmd += " --enablerepo=%s" % repo
        if self.disable_repo:
            for repo in self.disable_repo.split(","):
                cmd += " --disablerepo=%s" % repo

        if self.disable_plugin:
            # --disableplugin can take a comma separated list directly
            #for plugin in self.disable_plugin.split(","):
                #cmd += " --disableplugin=%s" % plugin
            cmd += " --disableplugin=%s" % self.disable_plugin

        if self.yum_config:
            for repo in self.yum_config.split(","):
                cmd += " --config=%s" % repo

        self.vprint(3, "running command: %s" % cmd)

        if OLD_PYTHON:
            self.vprint(3, "subprocess not available, probably old python " \
                         + "version, using shell instead")
            os.environ['LANG'] = "en_US"
            returncode, stdout = commands.getstatusoutput(cmd)
            if returncode >= 256:
                returncode = returncode / 256
        else:
            try:
                env = {'LANG': 'en_US'}
                process = Popen(cmd.split(), stdin=PIPE, stdout=PIPE, stderr=STDOUT, env=env)
            except OSError, error:
                error = str(error)
                if error == "No such file or directory":
                    end(UNKNOWN, "Cannot find utility '%s'" % cmd.split()[0])
                end(UNKNOWN, "Error trying to run utility '%s' - %s" \
                                                  % (cmd.split()[0], error))

            output = process.communicate()
            # for using debug outputs, either do not comment above line or explicitly set exit code below
            #output = [open(os.path.dirname(__file__) + '/test_input.txt').read(), '']
            returncode = process.returncode
            stdout = output[0]

        if not stdout:
            end(UNKNOWN, "No output from utility '%s'" % cmd.split()[0])

        self.vprint(3, "Returncode: '%s'\nOutput: '%s'" \
                                                     % (returncode, stdout))
        output = str(stdout).split("\n")
        self.check_returncode(returncode, output)

        return output


    def check_returncode(self, returncode, output):
        """Takes the returncode and output (as an array of lines)
        of the yum program execution and tests for failures, exits
        with an appropriate message if any are found"""

        if returncode == 0:
            for line in output:
                if "You must run this command as root" in line:
                    end(UNKNOWN, "You must run this plugin as root")
        elif returncode == 100:
            # Updates Available
            pass
        elif returncode == 200:
            if "lock" in output[-2] or "another copy is running" in output[-2]:
                msg = "Cannot check for updates, " \
                    + "another instance of yum is running"
                if self.no_warn_on_lock:
                    end(OK, msg)
                else:
                    end(WARNING, msg)
            else:
                output = self.strip_output(output)
                end(UNKNOWN, "%s" % output)
        else:
            if 'No more mirrors to try' in output:
                end(UNKNOWN, 'connectivity issue to repos: \'No more mirrors to try\'. ' + \
                             'You could also try running --cache-only and ' + \
                             'scheduling a separate \'yum makecache\' via cron or similar')
            elif (not ('Loading "security" plugin' in output or 'Loaded plugins:.*security' in output)) \
               or "Command line error: no such option: --security" in output:
                end(UNKNOWN, "Security plugin for yum is required. Try to "    \
                           + "'yum install yum-security' (RHEL5) or " \
                           + "'yum install yum-plugin-security' (RHEL6) and then re-run " \
                           + "this plugin. Alternatively, to just alert on "   \
                           + "any update which does not require the security " \
                           + "plugin, try --all-updates")
            else:
                output = self.strip_output(output)
                end(UNKNOWN, "%s" % output)


    def strip_output(self, output):
        """Cleans up the output from the plugin and returns it.
        Takes and returns an array of the lines of output
        and returns a single string"""

        self.vprint(3, "stripping output of 'Loading ... plugin' lines")
        re_loading_plugin = re.compile("^Loading .+ plugin$")
        output = [re_loading_plugin.sub("", line) for line in output]
        output = " ".join(output).strip()
        return output


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


    def sighandler(self, discarded, discarded2):
        """Function to be called by signal.alarm to kill the plugin"""

        # Nop for these variables
        discarded = discarded2
        discarded2 = discarded

        end(CRITICAL, "Yum nagios plugin has self terminated after " \
                    + "exceeding the timeout (%s seconds)" % self.timeout)


    def get_updates(self):
        """Checks for updates and returns a tuple containing the number of
        security updates and the number of total updates"""

        self.vprint(2, "checking for any security updates")

        if self.all_updates:
            number_security_updates, number_other_updates = \
                                                        self.get_all_updates()
        else:
            number_other_updates = self.get_security_updates()
            number_security_updates = 0

        return number_security_updates, number_other_updates


    def get_all_updates(self):
        """Gets all updates. Returns a single integer of the
        number of available updates"""

        cmd = "%s check-update" % YUM

        output = self.run(cmd)

        output2 = [_ for _ in "\n".join(output).split("\n\n") if  _]
        if self.verbosity >= 4:
            for section in output2:
                print "\nSection:\n%s\n" % section
        if len(output2) > 2 or \
           not ("Setting up repositories" in output2[0] or \
                "Loaded plugins: " in output2[0] or \
                re.search(r'Loading\s+".+"\s+plugin', output2[0])):
            end(WARNING, "Yum output signature does not match current known "  \
                       + "format. " + support_msg)
        number_packages = 0
        if len(output2) == 1:
            # There are no updates but we have passed
            # the loading and setting up of repositories
            pass
        else:
            for line in output2[1].split("\n"):
                if len(line.split()) > 1 and \
                   line[0:1] != " " and \
                   "Obsoleting Packages" not in line:
                    number_packages += 1

        try:
            number_packages = int(number_packages)
            if number_packages < 0:
                raise ValueError
        except ValueError:
            end(UNKNOWN, "Error parsing package information, invalid package " \
                       + "number, yum output may have changed. " + support_msg)

        # Extra layer of checks. This is a security plugin so it's preferable
        # to fail on error rather than pass silently leaving you with an
        # insecure system
        count = 0
        re_kernel_security_update = re.compile('^Security: kernel-.+ is an installed security update')
        re_kernel_update = re.compile('^Security: kernel-.+ is the currently running version')
        re_package_format = \
                re.compile(r'^.+\.(i[3456]86|x86_64|noarch)\s+.+\s+.+$')
        # This is to work around a yum truncation issue effectively changing
        # the package output format. Currently only very long kmod lines
        # are seen to have caused this so we stick to what we know for safety
        # and raise an unknown error on anything else for maximum security
        #re_package_format_truncated = \
        #        re.compile("^[\w-]+-kmod-\d[\d\.-]+.*\s+.+\s+.+$")
        obsoleting_packages = False
        for line in output:
            if ' excluded ' in line:
                continue
            elif obsoleting_packages and line[0:1] == " ":
                continue
            elif "Obsoleting Packages" in line:
                obsoleting_packages = True
                continue
            elif re_kernel_security_update.match(line):
                end(WARNING, 'Kernel security update is installed but requires a reboot')
            elif re_kernel_update.match(line):
                continue
            if re_package_format.match(line):
                count += 1
        if count != number_packages:
            end(UNKNOWN, "Error parsing package information, inconsistent "    \
                       + "package count (%d count vs %s num packages)" % (count, number_packages) \
                       + ", yum output may have changed. " + support_msg)

        return number_packages


    def get_security_updates(self):
        """Gets all updates, but differentiates between
        security and normal updates. Returns a tuple of the number
        of security and normal updates"""

        cmd = "%s --security check-update" % YUM

        output = self.run(cmd)

        re_security_summary = \
                re.compile(r'Needed (\d+) of (\d+) packages, for security')
        re_summary_rhel6 = re.compile(r'(\d+) package\(s\) needed for security, out of (\d+) available')
        re_no_sec_updates = \
                re.compile(r'No packages needed,? for security[;,] (\d+) (?:packages )?available')
        re_kernel_update = re.compile(r'^Security: kernel-.+ is an installed security update')
        summary_line_found = False
        for line in output:
            _ = re_summary_rhel6.match(line)
            if _:
                summary_line_found = True
                number_security_updates = _.group(1)
                number_total_updates = _.group(2)
                break
            _ = re_no_sec_updates.match(line)
            if _:
                summary_line_found = True
                number_security_updates = 0
                number_total_updates = _.group(1)
                break
            _ = re_security_summary.match(line)
            if _:
                summary_line_found = True
                number_security_updates = _.group(1)
                number_total_updates = _.group(2)
                break
            _ = re_kernel_update.match(line)
            if _:
                end(CRITICAL, "Kernel security update is installed but requires a reboot")

        if not summary_line_found:
            end(WARNING, "Cannot find summary line in yum output. " + support_msg)

        try:
            number_security_updates = int(number_security_updates)
            number_total_updates = int(number_total_updates)
        except ValueError:
            end(WARNING, "Error parsing package information, yum output " \
                       + "may have changed. " + support_msg)

        number_other_updates = number_total_updates - number_security_updates

        from_excluded_regex = re.compile(' from .+ excluded ')
        if len([_ for _ in output if not from_excluded_regex.search(_)]) > number_total_updates + 25:
            end(WARNING, "Yum output signature is larger than current known "  \
                       + "format. " + support_msg)

        return number_security_updates, number_other_updates


    def test_yum_updates(self):
        """Starts tests and controls logic flow"""

        check_yum_usable()
        self.vprint(3, "%s - Version %s\nAuthor: %s\n" \
            % (__title__, __version__, __author__))

        self.validate_all_variables()
        self.set_timeout()

        if self.all_updates:
            return self.test_all_updates()
        return self.test_security_updates()


    def test_all_updates(self):
        """Tests for all updates, and returns a tuple
        of the status code and output"""

        status = UNKNOWN
        message = "code error. " + support_msg

        number_updates = self.get_all_updates()
        if number_updates == 0:
            status = OK
            message = "0 Updates Available"
        else:
            status = CRITICAL
            if number_updates == 1:
                message = "1 Update Available"
            else:
                message = "%s Updates Available" % number_updates

        message += " | total_updates_available=%s" % number_updates

        return status, message


    def test_security_updates(self):
        """Tests for security updates and returns a tuple
        of the status code and output"""

        status = UNKNOWN
        message = "code error. " + support_msg

        number_security_updates, number_other_updates = \
                                                    self.get_security_updates()
        if number_security_updates == 0:
            status = OK
            message = "0 Security Updates Available"
        else:
            status = CRITICAL
            if number_security_updates == 1:
                message = "1 Security Update Available"
            elif number_security_updates > 1:
                message = "%s Security Updates Available" \
                                                    % number_security_updates

        if number_other_updates != 0:
            if self.warn_on_any_update and status != CRITICAL:
                status = WARNING
            if number_other_updates == 1:
                message += ". 1 Non-Security Update Available"
            else:
                message += ". %s Non-Security Updates Available" \
                                                        % number_other_updates
        message += " | security_updates_available=%s non_security_updates_available=%s total_updates_available=%s" \
                   % (number_security_updates, number_other_updates, number_security_updates + number_other_updates)

        return status, message


    def vprint(self, threshold, message):
        """Prints a message if the first arg is numerically greater than the
        verbosity level"""

        if self.verbosity >= threshold:
            print "%s" % message


def main():
    """Parses command line options and calls the test function"""

    tester = YumTester()
    parser = OptionParser()

    parser.add_option("-A",
                      "--all-updates",
                      action="store_true",
                      dest="all_updates",
                      help="Does not distinguish between security and "      \
                         + "non-security updates, but returns critical for " \
                         + "any available update. This may be used if the "  \
                         + "yum security plugin is absent or you want to "   \
                         + "maintain every single package at the latest "    \
                         + "version. You may want to use "                   \
                         + "--warn-on-any-update instead of this option")

    parser.add_option("-W",
                      "--warn-on-any-update",
                      action="store_true",
                      dest="warn_on_any_update",
                      help="Warns if there are any (non-security) package "   \
                         + "updates available. By default only warns when "   \
                         + "security related updates are available. If "      \
                         + "--all-updates is used, then this option is "      \
                         + "redundant as --all-updates will return a "        \
                         + "critical result on any available update, "        \
                         + "whereas using this switch still allows you to "   \
                         + "differentiate between the severity of updates ")

    parser.add_option("-C",
                      "--cache-only",
                      action="store_true",
                      dest="no_cache_update",
                      help="Run entirely from cache and do not update the " \
                         + "cache when running yum. Useful if you have "    \
                         + "'yum makecache' cronned so that the nagios "    \
                         + "check itself doesn't have to do it, possibly "  \
                         + "speeding up execution (by 1-2 seconds in tests)")

    parser.add_option("-c",
                      "--config",
                      dest="yum_config",
                      help="Run with custom repository config in order to use " \
                         + "custom repositories in case of special setup for")

    parser.add_option("-N",
                      "--no-warn-on-lock",
                      action="store_true",
                      dest="no_warn_on_lock",
                      help="Return OK instead of WARNING when yum is locked " \
                         + "and fails to check for updates due to another "   \
                         + "instance running. This is not recommended from "  \
                         + "the security standpoint, but may be wanted to "   \
                         + "reduce the number of alerts that may "            \
                         + "intermittently pop up when someone is running "   \
                         + "yum for package management")

    parser.add_option("-e",
                      "--enablerepo",
                      dest="repository_to_enable",
                      help="Explicitly enables a reposity when calling yum. " +
                      "Can take a comma separated list of repositories")

    parser.add_option("-d",
                      "--disablerepo",
                      dest="repository_to_disable",
                      help="Explicitly disables a repository when calling yum. " \
                         + "Can take a comma separated list of repositories")

    parser.add_option("--disableplugin",
                      dest="plugin_to_disable",
                      help="Explicitly disables a plugin when calling yum. " \
                         + "Can take a comma separated list of plugins")

    parser.add_option("-t",
                      "--timeout",
                      dest="timeout",
                      help="Sets a timeout in seconds after which the "  \
                          +"plugin will exit (defaults to %s seconds). " \
                                                      % DEFAULT_TIMEOUT)

    parser.add_option("-v",
                      "--verbose",
                      action="count",
                      dest="verbosity",
                      help="Verbose mode. Can be used multiple times to "     \
                         + "increase output. Use -vvv for debugging output. " \
                         + "By default only one result line is printed as "   \
                         + "per Nagios standards")

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
    tester.no_cache_update = options.no_cache_update
    tester.no_warn_on_lock = options.no_warn_on_lock
    tester.enable_repo = options.repository_to_enable
    tester.disable_repo = options.repository_to_disable
    tester.disable_plugin = options.plugin_to_disable
    tester.yum_config = options.yum_config
    tester.timeout = options.timeout
    tester.verbosity = options.verbosity
    tester.warn_on_any_update = options.warn_on_any_update

    if options.version:
        print "%s - Version %s\nAuthor: %s\n" \
            % (__title__, __version__, __author__)
        sys.exit(OK)

    result, output = tester.test_yum_updates()
    end(result, output)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print "Caught Control-C..."
        sys.exit(CRITICAL)
