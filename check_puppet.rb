#!/usr/bin/env ruby
#
#  Author: Hari Sekhon
#  Date: 2010-06-17 14:56:37 +0100 (Thu, 17 Jun 2010)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# I originally based this off the sample code provided in the 0.24.x puppet
# distribution but then I rewrote the whole thing, added more checks, leveraged
# puppet lib parsing and removed external sys/proctable dependency so this
# should just run anywhere puppet works without worrying about Gems.
# comm -1 -2 shows no lines in common apart from the #!/usr/bin/env ruby

# NOTE: client_yaml/catalog/$(hostname -f).yaml mtime updates every time puppet
# runs. When this is out of date, so too is state.yaml so we don't need an extra
# check for non-cached catalog runs since state.yaml covers it

# NOTE: considered adding a 'tail -n 100000 /var/log/messages | grep "Finished catalogue run in" | tail -n 1'
#       type check on the last successful run time, see nrpe/files/check_puppet_last_success.pl.
#       Update: this is not needed given the state check is robust and also puppet log strings change
#       between versions so can't be relied upon in the same way

require "optparse"
require "puppet"
require "puppet/defaults"
# require 'sys/proctable'
# include Sys

PUPPETD     = [ "/usr/sbin/puppetd", "/usr/bin/puppet", "/opt/puppetlabs/bin/puppet"]
PUPPET_CONF = "/etc/puppet/puppet.conf"

# Standard Nagios Exit Codes
EXIT = {
    "OK"       => 0,
    "WARNING"  => 1,
    "CRITICAL" => 2,
    "UNKNOWN"  => 3,
}

def quit(status, msg)
    puts "PUPPET #{status}: #{msg}"
    exit EXIT["#{status}"]
end

class CheckPuppet

    VERSION = '0.9.7'
    script_name = File.basename($0)

    # default options
    OPTIONS = {
        :conf        => "#{PUPPET_CONF}",
        :environment => "production",
        :warning     => 35, # mins
        :critical    => 70, # mins
    #    :lockfile    => "/var/lib/puppet/state/puppetdlock",
        :lockfile    => "",
    #    :statefile   => "/var/lib/puppet/state/state.yaml",
        :statefile   => "",
        :version     => nil,
        :verbose     => 0,
    }

    o = OptionParser.new do |o|
      o.set_summary_indent('    ')
      o.banner =    "usage: #{script_name} [OPTIONS]"
      o.separator   ""
      # o.define_head "The check_puppet Nagios plug-in checks that specified " +
      #              "Puppet process is running and the state file is no " +
      #              "older than specified interval."
      o.separator   "The #{script_name} Nagios plugin checks the following:\n" +
                    "1. No more than 2 'puppetd' or 'puppet agent' processes are running\n"  +
                    "2. Puppet has run successfully recently (state file has been updated)\n" +
                    "3. Puppet runs are enabled\n"         +
                    "4. The puppet version installed\n"    +
                    "5. The puppet environment the system is in\n"
      o.separator   ""
      # o.separator   "Mandatory arguments to long options are mandatory for " +
      #              "short options too."

      o.on("-C", "--config=value", String,
          "Default: #{PUPPET_CONF}")                 { |v| OPTIONS[:conf] = v }
      o.on("-e", "--environment=value", String,
          "Default: #{OPTIONS[:environment]}")       { |v| OPTIONS[:environment] = v }
      o.on("-w", "--warning=value", Integer,
          "Default: #{OPTIONS[:warning]} minutes")   { |v| OPTIONS[:warning] = v }
      o.on("-c", "--critical=value", Integer,
          "Default: #{OPTIONS[:critical]} minutes")  { |v| OPTIONS[:critical] = v }
      o.on("-l", "--lockfile=lockfile", String, "The lock file",
          "Default: uses puppet config / default") { |v| OPTIONS[:lockfile] = v }
      # o.on("-p", "--process=processname", String, "The process to check",
      #     "Default: #{OPTIONS[:process]}")           { |OPTIONS[:process]| }
      o.on("-s", "--statefile=statefile", String, "The state file",
          "Default: uses puppet config / default") { |v| OPTIONS[:statefile] = v }
      o.on("-v", "--verbose", String, "Verbose mode",
          "Default: off")                            { OPTIONS[:verbose] += 1 }
      o.on("-V", "--version=version", String, "The puppet version to expect",
          "Default: none")                           { |v| OPTIONS[:version] = v }

      o.separator ""
      o.on_tail("-h", "--help", "Show this help message.") do
          puts o
          exit EXIT["UNKNOWN"]
      end

      begin
          o.parse!(ARGV)
      rescue
          quit "UNKNOWN", "parsing error: " + $!.to_s
      end
    end

    unless File.exists?(OPTIONS[:conf])
        quit "UNKNOWN", "cannot find puppet conf file '#{OPTIONS[:conf]}'"
    end
    unless File.file?(OPTIONS[:conf])
        quit "UNKNOWN", "puppet conf file '#{OPTIONS[:conf]}' is not a regular file!"
    end
    unless File.readable?(OPTIONS[:conf])
        quit "UNKNOWN", "cannot read puppet conf file '#{OPTIONS[:conf]}'"
    end
    unless File.size?(OPTIONS[:conf])
        quit "UNKNOWN", "puppet conf file '#{OPTIONS[:conf]}' is empty!"
    end

    # Puppet lib config parsing fails silently on all error conditions!
    #
    # TODO: although I've added basic file tests above to catch obvious stuff
    # should consider adding validation of the conf file to make sure it's a
    # valid puppet conf file
    Puppet[:config] = OPTIONS[:conf]
    begin
        Puppet.initialize_settings unless Puppet.settings.send(:global_defaults_initialized?)
    rescue NameError
        Puppet.parse_config
    end

    if OPTIONS[:lockfile].empty?
        OPTIONS[:lockfile] = Puppet.settings.value(:agent_disabled_lockfile)
    end
    if OPTIONS[:statefile].empty?
        OPTIONS[:statefile] = Puppet.settings.value(:statefile)
    end

    def check_proc
        if OPTIONS[:verbose] > 1
            puts "checking puppet agent processes"
        end
        # num_procs = 0
        # ProcTable.ps{ |process|
        #     if process.cmdline.include? "puppetd" or process.cmdline.include? "puppet agent"
        #         num_procs += 1
        #     end
        # }
        procs = `ps -ef | grep -e 'puppet[d]\>' -e 'puppet agen[t]'`
        # On upgrades it has happened before where we have 2 procs running if
        # the old one doesn't exit properly so I check to make sure we have
        # exactly 1 proc running
        num_procs = procs.split("\n").size
        # if OPTIONS[:verbose] > 2
        #     puts "#{num_procs} puppet agent processes found"
        # end
        if procs.empty?
            @process_status = "CRITICAL"
            @process_msg    = "'puppetd/puppet agent' PROCESS NOT RUNNING"
        elsif num_procs > 2
            @process_status = "WARNING"
            @process_msg    = "#{num_procs} 'puppetd/puppet agent' PROCESSES RUNNING"
        elsif num_procs == 1 or num_procs == 2
            @process_status = "OK"
            @process_msg    = "#{num_procs} 'puppetd/puppet agent' process running"
        else
            @process_status = EXIT["UNKNOWN"]
            @process_msg    = "code error determining the number of 'puppetd/puppet agent' processes"
        end
    end

    def check_lastrun
        if OPTIONS[:verbose] > 1
            puts "checking puppet last run lag"
        end
        @warning  = OPTIONS[:warning]  * 60
        @critical = OPTIONS[:critical] * 60
        if @warning < 1
            quit "UNKNOWN", "warning threshold must be greater than 0!"
        elsif @critical < 1
            quit "UNKNOWN", "critical threshold must be greater than 0!"
        elsif @warning > @critical
            quit "UNKNOWN", "warning threshold cannot be higher than critical threshold!"
        end

        now       = Time.now
        begin
            mtime = File.mtime("#{OPTIONS[:statefile]}")
        rescue
            quit "UNKNOWN", "failed to get mtime of state file '#{OPTIONS[:statefile]}'"
        end

        @diff = (now - mtime).to_i

        # if OPTIONS[:verbose] > 2
        #     puts "#{@diff} second lag since last puppet run completed"
        # end
        if @diff > @critical
            @lastrun_status = "CRITICAL"
            @lastrun_msg    = "STATE FILE " + @diff.to_s + " SECONDS OLD"
        elsif @diff > @warning
            @lastrun_status = "WARNING"
            @lastrun_msg    = "STATE FILE " + @diff.to_s + " SECONDS OLD"
        else
            @lastrun_status = "OK"
            @lastrun_msg = "state file last updated " + @diff.to_s + " seconds ago"
        end
        @lastrun_msg = @lastrun_msg + " (w=#{@warning}/c=#{@critical})"
    end

    def check_enabled
        if OPTIONS[:verbose] > 1
            puts "checking puppet is enabled"
        end
        if FileTest.exist?("#{OPTIONS[:lockfile]}")
            # This used to be the case pre 2.6, not supporting that any more
            # if File.zero?("#{OPTIONS[:lockfile]}")
                @enabled_status = "CRITICAL"
                @enabled_msg = "PUPPET RUNS DISABLED"
            # else
            #    @enabled_status = "OK"
            #    @enabled_msg = "puppet runs enabled (currently in progress)"
            # end
        else
            @enabled_status = "OK"
            @enabled_msg = "puppet runs enabled"
        end
    end

    def check_version
        for puppet in PUPPETD
            if FileTest.exist? puppet
                puppet_version_cmd = "#{puppet} -V"
                break
            end
        end
        unless defined? puppet_version_cmd
            quit "UNKNOWN", "failed to find puppet command to test version"
        end
        @puppet_version = `#{puppet_version_cmd}`.chomp
        unless /^\d+(\.\d+)+$/.match(@puppet_version)
            quit "UNKNOWN", "version retrieved from '#{puppet_version_cmd}' did not match expected regex (returned '#{@puppet_version}')"
        end
        if OPTIONS[:version]
            if OPTIONS[:verbose] > 1
                puts "checking puppet version"
            end
            if @puppet_version == OPTIONS[:version]
                @version_status = "OK"
            else
                @version_status = "CRITICAL"
            end
        else
            @version_status = "OK"
        end
        case @version_status
            when "OK"
                @version_msg = "puppet version #{@puppet_version}"
            else
                @version_msg = "PUPPET VERSION #{@puppet_version} (expected '#{OPTIONS[:version]}')"
        end
    end

    def check_environment
        if OPTIONS[:verbose] > 1
            puts "checking puppet environment"
        end
        @puppet_environment = "production"
        facter_environment  = `RUBYLIB=$RUBYLIB:/var/lib/puppet/lib facter | grep ^environment`.chomp!
        agent_regex         = Regexp.compile('^\s*\[\s*(?:agent|puppetd)\s*\]\s*$')
        section_regex       = Regexp.compile('^\s*\[\s*[^\]]*\]\s*\]\s*$')
        environment_regex   = Regexp.compile('^\s*environment\s*=\s*(.+?)\s*$')

        # This is actually wrong, I've tested when this goes in to staging environment
        # Puppet.settings.value(:environment) still returns "production" which is broken
        @puppet_environment = Puppet.settings.value("environment")
        file = File.open("#{OPTIONS[:conf]}", 'r')
        until (file.eof?)
            f = file.readline.chomp!
            next unless agent_regex.match(f)
            break
        end
        until (file.eof?)
            f = file.readline.chomp!
            break if section_regex.match(f)
            next unless environment_regex.match(f)
            @puppet_environment = $1
        end
        file.close
        if facter_environment and not facter_environment.empty?
            facter_environment = facter_environment.gsub(/^environment => /, "")
            unless facter_environment.empty?
                @puppet_environment = facter_environment
            end
        elsif ENV['FACTER_environment'] and not ENV['FACTER_environment'].empty?
            @puppet_environment = ENV['FACTER_environment']
        end
        if @puppet_environment == OPTIONS[:environment]
            @environment_status = "OK"
            @environment_msg    = "environment '#{@puppet_environment}'"
        else
            @environment_status = "WARNING"
            @environment_msg    = "ENVIRONMENT '#{@puppet_environment}' (expected '#{OPTIONS[:environment]}')"
        end
    end

    def quit_status
        status = "OK"
        for x in [@process_status, @lastrun_status, @enabled_status, @version_status, @environment_status]
            if EXIT["#{x}"] > EXIT["#{status}"]
                status = x unless status == "CRITICAL"
            end
        end
        quit status,
            @process_msg      + ", " +
            @lastrun_msg      + ", " +
            @enabled_msg      + ", " +
            @version_msg      + ", " +
            @environment_msg  +
            " | state_file_age=" + @diff.to_s + "s;" + @warning.to_s + ";" + @critical.to_s
    end

    def check_puppet
        check_proc
        check_lastrun
        check_enabled
        check_version
        check_environment
        quit_status
    end
end

begin
    cp = CheckPuppet.new
    cp.check_puppet
rescue
    quit "UNKNOWN", "code error: " + $!
end

quit "UNKNOWN", "code error, hit end of plugin"
