#!/usr/bin/env python
#
#  Author: Hari Sekhon
#  Date: 2007-11-20 18:16:55 +0000 (Tue, 20 Nov 2007)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

"""Nagios plugin to parse the ISC Dhcp Server lease file and print out a list
of all the Name/IP/MAC associations or any combination of the three. Can also
be used to alert on the delegation of IPs to non-recognized MACs or Hostnames"""

__author__  = "Hari Sekhon"
__title__   = "Nagios Plugin for DHCPd Server Leases"
__version__ = '0.8.4'

# Due to the limited of characters that Nagios accepts from a plugin, this
# output will be cut short if you have a lot of dhcp clients, which is why
# the -c switch was included to compact the output to fit more in.

# Remember, this program can be used without Nagios so that character limit
# need not be your limit.

import re
import sys
import signal
from optparse import OptionParser

# Standard Nagios return codes
OK       = 0
WARNING  = 1
CRITICAL = 2
UNKNOWN  = 3

# Default timeout. All good plugins should have a timeout to prevent hanging
TIMEOUT  = 30

# Regex for lease comparison and dissection
RE_BINDING_STATE_ACTIVE = re.compile(r'\s*binding state active;')
RE_LEASE                = re.compile(r'lease')
RE_HOSTNAME             = re.compile(r'client-hostname')
RE_MAC                  = re.compile(r'hardware\sethernet')
RE_IP_ADDRESS           = re.compile(r'(\d{1,3}.){3}\d{1,3}')

def end(status, message):  # lgtm [py/similar-function]
    """Exits the plugin with first arg as the return code and the second
    arg as the message to output"""

    if status == OK:
        print("DHCP LEASES: %s" % message)
        sys.exit(OK)
    elif status == WARNING:
        print("WARNING: %s" % message)
        sys.exit(WARNING)
    elif status == CRITICAL:
        print("CRITICAL: %s" % message)
        sys.exit(CRITICAL)
    else:
        print("UNKNOWN: %s" % message)
        sys.exit(UNKNOWN)


def sort_keys_by_host(dictionary):
    """Takes the address dictionary in the form {"ip":["hostname","mac"]},
    sorts the keys by the host value, returns an ordered list of keys"""

    hosts = []
    keys = list(dictionary.keys())
    keys.sort()
    keys_sorted = []
    for key in keys:
        hosts.append(dictionary[key][0])
    hosts.sort()
    for host in hosts:
        for key in keys:
            if dictionary[key][0] == host:
                keys_sorted.append(key)

    # ((k, v) for k, v in mydict), key=lambda i: i[1])

    # dedup without losing order
    keys_sorted2 = []
    for key in keys_sorted:
        if key not in keys_sorted2:
            keys_sorted2.append(key)
    keys_sorted = keys_sorted2

    return keys_sorted


class DhcpdLeaseTester:
    """Class to hold all Dhcpd Lease test state"""

    def __init__(self):
        """Instantiate variables"""

        self.address_dict      = {}
        self.compact_output    = False
        self.host_whitelist    = ""
        self.host_blacklist    = ""
        self.leasefile         = None
        self.lease             = ""
        self.leases            = []
        self.mac_whitelist     = ""
        self.mac_blacklist     = ""
        self.no_name           = False
        self.no_summary        = False
        self.show_mac          = False
        self.sort_by_ip        = False
        self.timeout           = TIMEOUT
        self.unauthorized      = False
        self.unauthorized_dict = {}

    def validate_variables(self):
        """Validates all variables as defined in self.__init__"""

        if self.compact_output is None:
            self.compact_output = False
        if self.host_whitelist is None:
            self.host_whitelist = ""
        if self.host_blacklist is None:
            self.host_blacklist = ""
        if self.leasefile is None:
            end(UNKNOWN, "No leasefile to test")
        if self.mac_whitelist is None:
            self.mac_whitelist = ""
        if self.mac_blacklist is None:
            self.mac_blacklist = ""

        if self.timeout is None:
            self.timeout = TIMEOUT

        self.validate_normalize_macs("whitelist")
        self.validate_normalize_macs("blacklist")

        try:
            self.timeout = int(self.timeout)
        except ValueError:
            end(UNKNOWN, "timeout invalid, must be a numeric integer")


    def validate_normalize_macs(self, colourlist):
        """Checks to make sure any Mac addresses given
        are in the correct format. Takes either whitelist or blacklist
        and then validates each mac in that list and changes the list
        to a normalized uppercase hex mac with no formatting or
        separators"""

        maclist = getattr(self, "mac_" + colourlist)
        maclist = maclist.replace(",", " ")
        maclist = maclist.split()
        maclist = [mac.replace(":","") for mac in maclist]
        maclist = [mac.upper() for mac in maclist]

        re_mac_format = re.compile(r'^([\dA-Fa-f]{2}[:-]?){5}[\dA-Fa-f]{2}$')

        for mac in maclist:
            if not re_mac_format.match(mac):
                end(UNKNOWN, "'%s' was given as a Mac address but is " % mac
                           + "not a valid Mac")

        setattr(self, "mac_" + colourlist, maclist)


    def sighandler(self, _discarded, _discarded2):
        """Function to be called by signal.alarm to kill the plugin"""

        end(CRITICAL, "plugin has self terminated after exceeding " \
                    + "the timeout (%s seconds)" % self.timeout)


    def test_leases(self):
        """Initiates the test, calls parse_leases and possibly the condition
        checking funcs too if whitelist or blacklists are used"""

        self.validate_variables()

        signal.signal(signal.SIGALRM, self.sighandler)
        signal.alarm(self.timeout)

        # In the format {"ip":["hostname","mac"]}
        self.address_dict = {}

        result = OK

        try:
            output = self.parse_leases()
        except IndexError:
            end(CRITICAL, "Error parsing dhcp leases file '%s', possibly not " \
                        + "valid lease file?" % self.leasefile)

        self.check_unauthorized_leases()

        if self.unauthorized:
            unauthorized_output = self.format_unauthorized_leases()
            output = unauthorized_output + " || " + output
            result = CRITICAL

        # When we used to compact the whitespace out, not used any more
        #if self.compact_output:
        #    output = output.replace(" - ", "-")
        #    output = output.replace(" = ", "=")
        #    output = output.replace(", ", ",")
        #    output = output.replace(" (", "(")
        #    output = output.replace(" | ", "|")

        return result, output


    def parse_leases(self):
        """Parse leases file and returns a string of leases with IP addreses
        and optional Hostname/Mac mappings"""

        self.leases = self.open_lease_file()

        security_checks_on = False
        if self.host_whitelist or \
           self.host_blacklist or \
           self.mac_whitelist  or \
           self.mac_blacklist:
            security_checks_on = True

        for self.lease in self.leases:
            if RE_BINDING_STATE_ACTIVE.search(self.lease):
                hostname = ""
                ip       = ""
                mac      = ""

                self.lease = self.lease.split("\n")

                ip = self.get_ip()
                # If this is not valid, there can be no lease so move on
                # This actually catches things like the user not using a decent
                # lease file, in which case this will result in no real leases
                # and will therefore result in a true result of no leases.
                # Actually forcing the correct lease file turned out to not
                # be fully possible since it varies among servers, so this
                # catches the rest
                if ip == "UNKNOWN":
                    continue
                self.address_dict[ip] = ["Unknown Hostname", "Unknown Mac"]
                if not self.no_name or security_checks_on:
                    hostname = self.get_hostname()
                    self.address_dict[ip][0] = hostname

                if self.show_mac or security_checks_on:
                    mac = self.get_mac()
                    self.address_dict[ip][1] = mac

        msg = self.format_leases()

        return msg


    def check_unauthorized_leases(self):
        """Checks for and call functions to test the leases against the given
        whitelists/blacklists. Returns a list where the first element is a True
        or False overall result, and the second element is a dictionary of
        offending hosts with 'mac' and 'host' keys representing an array of
        hosts that tripped each type of rule"""

        if self.mac_whitelist:
            self.check_mac_whitelist()

        if self.mac_blacklist:
            self.check_mac_blacklist()

        if self.host_whitelist:
            self.check_host_whitelist()

        if self.host_blacklist:
            self.check_host_blacklist()

        if self.unauthorized_dict:
            self.unauthorized = True


    def check_host_whitelist(self):
        """Checks the self.address_dict for any hostname not in the host
        whitelist and returns a list of unauthorized hostnames"""

        host_whitelist = self.host_whitelist.replace(",", " ")
        host_whitelist = host_whitelist.split()
        host_whitelist = [host.upper() for host in host_whitelist]

        for ip in self.address_dict:
            hostname = self.address_dict[ip][0]
            mac      = self.address_dict[ip][1]
            if hostname.upper() not in host_whitelist:
                self.unauthorized_dict[ip] = (hostname, mac)


    def check_host_blacklist(self):
        """Checks the self.address_dict for any hostname not in the host
        blacklist and returns a list of unauthorized hostnames"""

        host_blacklist = self.host_blacklist.replace(",", " ")
        host_blacklist = host_blacklist.split()
        host_blacklist = [host.upper() for host in host_blacklist]

        for ip in list(self.address_dict.keys()):
            hostname = self.address_dict[ip][0]
            mac      = self.address_dict[ip][1]
            if hostname.upper() in host_blacklist:
                self.unauthorized_dict[ip] = (hostname, mac)


    def check_mac_whitelist(self):
        """Checks the self.address_dict for any macname not in the mac
        whitelist and returns a list of unauthorized macnames"""

        for ip in list(self.address_dict.keys()):
            hostname = self.address_dict[ip][0]
            mac      = self.address_dict[ip][1]
            mac      = mac.replace(":", "")
            mac      = mac.upper()
            if mac not in self.mac_whitelist:
                self.unauthorized_dict[ip] = (hostname, mac)


    def check_mac_blacklist(self):
        """Checks the self.address_dict for any macname not in the mac
        blacklist and returns a list of unauthorized macnames"""

        for ip in list(self.address_dict.keys()):
            hostname = self.address_dict[ip][0]
            mac      = self.address_dict[ip][1]
            mac      = mac.replace(":", "")
            mac      = mac.upper()
            if mac in self.mac_blacklist:
                self.unauthorized_dict[ip] = (hostname, mac)


    def format_leases(self):
        """Takes the address dictionary in the form {"ip":("hostname","mac")}
        and formats the output, returns a string."""

        if self.no_name:
            self.sort_by_ip = True

        if self.sort_by_ip:
            address_keys_sorted = list(self.address_dict.keys())
            address_keys_sorted.sort()
        else:
            address_keys_sorted = sort_keys_by_host(self.address_dict)

        number_leases = len(address_keys_sorted)
        if number_leases == 0:
            msg = "No dhcp leases recorded"
        else:
            if self.no_summary:
                msg = ""
            else:
                if number_leases == 1:
                    msg = "%s lease" % number_leases
                else:
                    msg = "%s leases" % number_leases
                if not self.compact_output:
                    msg += " - "
            if not self.compact_output:
                for ip in address_keys_sorted:
                    if self.no_name:
                        msg += "%s" % ip
                    else:
                        hostname = self.address_dict[ip][0]
                        msg += "%s = %s" % (hostname, ip)
                    if self.show_mac:
                        mac = self.address_dict[ip][1]
                        msg += " (%s)" % mac
                    msg += ", "
                msg = msg.rstrip(", ")

            msg += " | 'DHCP Leases'=%s" % number_leases

        return msg


    def format_unauthorized_leases(self):
        """Takes the self unauthorized dictionary in the form
        {"ip":("hostname","mac","offending")}
        and formats the output, returns a string."""

        if self.no_name:
            self.sort_by_ip = True

        if self.sort_by_ip:
            unauthorized_keys_sorted = list(self.unauthorized_dict.keys())
            unauthorized_keys_sorted.sort()
        else:
            unauthorized_keys_sorted = sort_keys_by_host(self.unauthorized_dict)

        number_unauthorized = len(unauthorized_keys_sorted)
        if number_unauthorized == 0:
            return ""
        else:
            if number_unauthorized == 1:
                msg = "%s Unauthorized Host! " % number_unauthorized
            else:
                msg = "%s Unauthorized Hosts! " % number_unauthorized
            for ip in unauthorized_keys_sorted:
                if self.no_name:
                    msg += "%s" % ip
                else:
                    hostname = self.unauthorized_dict[ip][0]
                    msg += "%s = %s" % (hostname, ip)
                if self.show_mac:
                    # Get original instead as Mac has changed by this point
                    # This maintains better output consistency but relies
                    # on the leases file being slightly sane..., but then
                    # if your leases file is not sane, how is that my fault?
                    # This would be a failing of dhcpd more than this plugin
                    #mac = self.unauthorized_dict[ip][1]
                    mac = self.address_dict[ip][1]
                    msg += " (%s)" % mac
                msg += ", "

            msg = msg.rstrip(", ")

        return msg


    def open_lease_file(self):
        """Opens the lease file, tests the lease file is valid, and then returns
        an array of elements each containing one lease block definition"""

        leases_array = []

        try:
            file_handle = open(self.leasefile)
            leases      = file_handle.read()
        except IOError:
            end(CRITICAL, "Error reading lease file '%s'" % self.leasefile)

        # Check to see if it is a valid lease file.
        # If there are no leases, then we should check that there are some
        # header keywords comment that you usually seen in a dhcpd.leases file

        # This isn't really good enough but otherwise it can break across
        # different systems. Looser than I would like but the user should
        # really be using a valid lease file. Parse leases will also catch
        # this in that no leases will be created and the result will be
        # technically true, there are no valid leases in an incorrect file
        if not re.search(r'\n\s*lease .+{\s*\n', leases) \
            and not \
                re.search("(?i)\n#.*lease[s]? file .* written by.*\n", leases) \
            and not re.search("\n#.*dhcpd.leases.*\n", leases) \
            and not re.search("\n(?i)#.*isc-dhcp.*\n", leases):
            end(CRITICAL, "'%s' is not recognized as a valid dhcpd lease file" \
                                                               % self.leasefile)

        leases = leases.split("}")[:-1]
        for lease in leases:
            lease_parts = lease.split("{")
            if len(lease_parts) > 1:
                leases_array.append(lease_parts[1])
            #else:
            #    print >> sys.stderr, "Debug - Not valid lease:\n%s" % lease

        return leases


    def get_ip(self):
        """Takes an list of lines from a dhcp lease block from self.leases
        and returns the ip address of this lease"""

        ip = ""

        for line in self.lease:
            if RE_LEASE.search(line):
                line = line.split()
                if len(line) == 3:
                    ip = line[1]
                else:
                    ip = "UNKNOWN"

        if not RE_IP_ADDRESS.match(ip):
            ip = "UNKNOWN"

        return ip


    def get_hostname(self):
        """Takes an list of lines from a dhcp lease block from self.leases
        and returns the hostname of the machine with this lease"""

        hostname = ""

        for line in self.lease:
            if RE_HOSTNAME.search(line):
                line = line.split()
                if len(line) == 2:
                    hostname = line[1]
                    hostname = hostname.rstrip(";")
                    hostname = hostname.strip('"')
                else:
                    hostname = "UNKNOWN"

        if not hostname:
            hostname = "UNKNOWN"

        return hostname


    def get_mac(self):
        """Takes an list of lines from a dhcp lease block from self.leases
        and returns the Mac of the machine with this lease"""

        mac = ""

        for line in self.lease:
            if RE_MAC.search(line):
                line = line.split()
                if len(line) == 3:
                    mac = line[2]
                    mac = mac.rstrip(";")
                else:
                    mac = "UNKNOWN"

        if not mac:
            mac = "UNKNOWN"

        return mac


def main():
    """Main func parses command line args and calls print_leases"""

    tester = DhcpdLeaseTester()
    parser = OptionParser()
    parser.add_option( "-c",
                       "--compact-output",
                       action="store_true",
                       dest="compact_output",
                       help="Compact the output, do not list leases. Use this" \
                          + "to make sure Nagios gets perfdata as NRPE has" \
                          + " a limit on the number of characters before it "  \
                          + "discards the rest")
    parser.add_option( "-f",
                       "--file",
                       "--lease-file",
                       dest="leasefile",
                       help="Specify the dhcp lease file to use. Should be "  \
                          + "the current lease file that the ISC dhcp "       \
                          + "daemon uses to track it's leases")
    parser.add_option( "-m",
                       "--mac",
                       action="store_true",
                       dest="show_mac",
                       help="Show mac addresses as well as Name/IP pairings")
    parser.add_option( "-n",
                       "--no-name",
                       action="store_true",
                       dest="no_name",
                       help="Do not display hostnames. When used by itself, "  \
                          + "this just shows assigned IP addresses. Can be "   \
                          + "used in conjunction with --mac in order to show " \
                          + "only IP/Mac pairings")
    parser.add_option( "-i",
                       "--sort-by-ip",
                       action="store_true",
                       dest="sort_by_ip",
                       help="Change the output order to sort by IP rather "    \
                          + "than the default of sorting by hostname. If "     \
                          + "using --no-name this is implied")
    parser.add_option( "-s",
                       "--no-summary",
                       action="store_true",
                       dest="no_summary",
                       help="Do not print the summary of the number of dhcp "  \
                          + "leases used")
    parser.add_option( "-t",
                       "--timeout",
                       dest="timeout",
                       help="Timeout in seconds before the plugin self "       \
                          + "terminates. This should never be needed but the " \
                          + "Nagios coding guidelines recommend it and "       \
                          + "therefore it is implemented for completeness. "   \
                          + "Use this to specify a custom timeout period in "  \
                          + "seconds (should be an integer/whole number). "    \
                          + "Defaults to %s seconds" % TIMEOUT)
    parser.add_option( "-w",
                       "--host-whitelist",
                       dest="host_whitelist",
                       help="Whitelist of known Hostnames. Raises alert"       \
                          + " if an IP has been issued to any machine with a " \
                          + "Hostname not in this list. Considered weak since" \
                          + " the hostname can be set on the client machine "  \
                          + "before requesting a dhcp lease. But it's there "  \
                          + "if you want it. Can be a nice extra layer to the" \
                          + " defense in depth strategy when properly used "   \
                          + "with a Mac whitelist as well. Although Mac "      \
                          + "addresses can also be spoofed, some attackers "   \
                          + "may not think to spoof the hostname as well as"   \
                          + " the mac address. Should be a comma or space "    \
                          + "separated list, enclosed in quotes if using "     \
                          + "spaces. Hostnames are case insensitive")
    parser.add_option( "-x",
                       "--host-blacklist",
                       dest="host_blacklist",
                       help="Blacklist of known Hostnames. Raises "            \
                          + "alert if an IP has been handed out to a machine " \
                          + "with this Hostname. Can take a list of Hostnames" \
                          + ", comma or space separated (enclose in quotes if" \
                          + " using spaces). Can be combined with any "        \
                          + "Whitelist, in which case, blacklists always take" \
                          + " preference over whitelists and raise an alert. " \
                          + "Hostnames are case insensitive")
    parser.add_option( "-y",
                       "--mac-whitelist",
                       dest="mac_whitelist",
                       help="Whitelist of known Mac addresses. Raises "        \
                          + "alert if an IP has been issued to any machine "   \
                          + "with a Mac address not in this list. Although "   \
                          + "Mac addresses can be spoofed, this may not have " \
                          + "been done when requesting the dhcp lease. For "   \
                          + "extra layers combine with --host-whitelist to "   \
                          + "form a nice additional tripwire. Should be a "    \
                          + "comma or space separated list, enclosed in "      \
                          + "quotes if using spaces. Valid Mac formats: "      \
                          + "aa:bb:cc:dd:ee:ff, or aa-bb-cc-dd-ee-ff or "      \
                          + "aabbccddeeff (case insensitive)")
    parser.add_option( "-z",
                       "--mac-blacklist",
                       dest="mac_blacklist",
                       help="Blacklist of known Mac addresses. Raises "        \
                          + "alert if an IP has been handed out to a machine " \
                          + "with this Mac address. Can take a list of Macs"   \
                          + ", comma or space separated (enclose in quotes if" \
                          + " using spaces). Can be combined with any "        \
                          + "Whitelist, in which case, blacklists always take" \
                          + " preference over whitelists and raise an alert. " \
                          + "Valid Mac formats: aa:bb:cc:dd:ee:ff, or "        \
                          + "aa-bb-cc-dd-ee-ff or aabbccddeeff (case "         \
                          + "insensitive)")
    parser.add_option( "-V",
                        "--version",
                        action = "store_true",
                        dest = "version",
                        help = "Print version number and exit" )

    (options, args) = parser.parse_args()


    tester.compact_output = options.compact_output
    tester.host_whitelist = options.host_whitelist
    tester.host_blacklist = options.host_blacklist
    tester.leasefile      = options.leasefile
    tester.mac_whitelist  = options.mac_whitelist
    tester.mac_blacklist  = options.mac_blacklist
    tester.no_name        = options.no_name
    tester.no_summary     = options.no_summary
    tester.show_mac       = options.show_mac
    tester.sort_by_ip     = options.sort_by_ip

    timeout               = options.timeout
    version               = options.version

    if args:
        parser.print_help()
        sys.exit(UNKNOWN)

    if version:
        print(__version__)
        sys.exit(UNKNOWN)

    if not tester.leasefile:
        print("UNKNOWN: no lease file specified. See --help for details\n")
        parser.print_help()
        sys.exit(UNKNOWN)

    if timeout is None:
        timeout = TIMEOUT

    try:
        tester.timeout = int(timeout)
    except ValueError:
        end(UNKNOWN, "timeout must be a numeric integer. See --help for " \
                   + "details")

    result, output = tester.test_leases()

    end(result, output)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Caught Control-C...")
        sys.exit(UNKNOWN)
