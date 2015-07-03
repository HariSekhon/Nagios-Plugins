#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#
#  http://github.com/harisekhon
#

ifdef TRAVIS
    SUDO2 =
else
    SUDO2 = sudo
endif

# EUID /  UID not exported in Make
ifeq '$(USER)' 'root'
    SUDO =
    SUDO2 =
else
    SUDO = sudo
endif

.PHONY: make
make:
	[ -x /usr/bin/apt-get ] && make apt-packages || :
	[ -x /usr/bin/yum ]     && make yum-packages || :
	
	git submodule init
	git submodule update

	cd lib && make

	# There are problems with the tests for this module dependency of Net::Async::CassandraCQL, forcing install works and allows us to use check_cassandra_write.pl
	#sudo cpan -f IO::Async::Stream

	# XXX: there is a bug in the Readonly module that MongoDB::MongoClient uses. It tries to call Readonly::XS but there is some kind of MAGIC_COOKIE mismatch and Readonly::XS errors out with:
	#
	# Readonly::XS is not a standalone module. You should not use it directly. at /usr/local/lib64/perl5/Readonly/XS.pm line 34.
	#
	# Workaround is to edit Readonly.pm and comment out line 33 which does the eval 'use Readonly::XS';
	# On Linux this is located at:
	#
	# /usr/local/share/perl5/Readonly.pm
	#
	# On my Mac OS X Mavericks:
	#
	# /Library/Perl/5.16/Readonly.pm

	# Required to successfully build the MongoDB module for For RHEL 5
	#sudo cpan Attribute::Handlers
	#sudo cpan Params::Validate
	#sudo cpan DateTime::Locale DateTime::TimeZone
	#sudo cpan DateTime

	# You may need to set this to get the DBD::mysql module to install if you have mysql installed locally to /usr/local/mysql
	#export DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH:/usr/local/mysql/lib/"

	@#@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	@# putting modules one per line just for ease of maintenance
	#
	# add -E to sudo to preserve http proxy env vars or run this manually if needed (only works on Mac)
	# Redis module required but didn't auto-pull: ExtUtils::Config ExtUtils::Helpers ExtUtils::InstallPaths TAP::Harness::Env Module::Build::Tiny Sub::Name
	# Kafka module required but didn't auto-pull: ExtUtils::Config, ExtUtils::Helpers, ExtUtils::InstallPaths, TAP::Harness::Env, Module::Build::Tiny, Sub::Exporter::Progressive, Const::Fast, Exporter::Tiny, List::MoreUtils, Devel::CheckLib, Compress::Snappy, Sub::Name
	# Module::CPANfile::Result and Module::Install::Admin are needed for Hijk which is auto-pulled by Search::Elasticsearch but doesn't auto-pull Module::CPANfile::Result
	# Module::Build::Tiny and Const::Fast must be built before Kafka, doesn't auto-pull in correct order
	# Proc::Daemon needed by Kafka::TestInternals
	# Proc::Daemon fails on tests, force install anyway to appease Travis
	yes "" | $(SUDO2) cpan App::cpanminus
	yes "" | $(SUDO2) cpanm --notest \
		YAML \
		Module::Build::Tiny \
		Const::Fast \
		Class::Accessor \
		Compress::Snappy \
		Proc::Daemon \
		DBD::mysql \
		DBI \
		Data::Dumper \
		Devel::CheckLib \
		Digest::SHA \
		Exporter::Tiny \
		ExtUtils::Config \
		ExtUtils::Constant \
		ExtUtils::Helpers \
		ExtUtils::InstallPaths \
		IO::Socket::IP \
		IO::Socket::SSL \
		JSON \
		JSON::XS \
		Kafka \
		LWP::Authen::Negotiate \
		LWP::Simple \
		LWP::UserAgent \
		List::MoreUtils \
		Math::Round \
		Module::CPANfile::Result \
		Module::Install::Admin \
		MongoDB \
		MongoDB::MongoClient \
		Net::DNS \
		Net::LDAP \
		Net::LDAPI \
		Net::LDAPS \
		Net::SSH::Expect \
		Readonly \
		Readonly::XS \
		Redis \
		Search::Elasticsearch \
		SMS::AQL \
		Sub::Exporter::Progressive \
		Sub::Name \
		TAP::Harness::Env \
		Test::SharedFork \
		Thrift \
		Time::HiRes \
		Type::Tiny::XS \
		URI::Escape \
		XML::SAX \
		XML::Simple \
		; echo
		#Net::Async::CassandraCQL \
	# Intentionally ignoring CPAN module build failures since some modules may fail for a multitude of reasons but this isn't really important unless you need the pieces of code that use them in which case you can solve those dependencies later
	
	# newer version of setuptools (>=0.9.6) is needed to install cassandra-driver
	# might need to specify /usr/bin/easy_install or make /usr/bin first in path as sometimes there are version conflicts with Python's easy_install
	$(SUDO) easy_install -U setuptools || :
	$(SUDO) easy_install pip || :
	# cassandra-driver is needed for check_cassandra_write.py + check_cassandra_query.py
	$(SUDO) pip install cassandra-driver scales blist lz4 python-snappy || :
	
	# install MySQLdb python module for check_logserver.py / check_syslog_mysql.py
	# fails if MySQL isn't installed locally
	$(SUDO) pip install MySQL-python || :


.PHONY: apt-packages
apt-packages:
	# needed to fetch and build CPAN modules and fetch the library submodule at end of build
	dpkg -l build-essential libwww-perl git &>/dev/null || $(SUDO) apt-get install -y build-essential libwww-perl git || :
	# for DBD::mysql as well as headers to build DBD::mysql if building from CPAN
	dpkg -l libdbd-mysql-perl libmysqlclient-dev &>/dev/null || $(SUDO) apt-get install -y libdbd-mysql-perl libmysqlclient-dev || :
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	dpkg -l libssl-dev &>/dev/null || $(SUDO) apt-get install -y libssl-dev || :
	# for XML::Simple building
	dpkg -l libexpat1-dev &>/dev/null || $(SUDO) apt-get install -y libexpat1-dev || :
	# for check_whois.pl
	dpkg -l jwhois &>/dev/null || $(SUDO) apt-get install -y jwhois || :
	# TODO: for LWP::Authenticate - prompts for realm + KDC, probably automatable but not tested yet
	#apt-get install -y krb5-config || :
	# for Cassandra's Python driver
	#dpkg -l python-setuptools python-dev libev4 libev-dev libsnappy-dev &>/dev/null ||
	$(SUDO) apt-get install -y python-setuptools python-dev libev4 libev-dev libsnappy-dev || :

.PHONY: yum-packages
yum-packages:
	rpm -q gcc gcc-c++ perl-CPAN perl-libwww-perl git || $(SUDO) yum install -y gcc gcc-c++ perl-CPAN perl-libwww-perl git || :
	# for DBD::mysql as well as headers to build DBD::mysql if building from CPAN
	rpm -q perl-DBD-MySQL mysql-devel || $(SUDO) yum install -y perl-DBD-MySQL mysql-devel || :
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	rpm -q openssl-devel || $(SUDO) yum install -y openssl-devel || :
	# for XML::Simple building
	rpm -q expat-devel || $(SUDO) yum install -y expat-devel || :
	# for check_whois.pl
	rpm -q jwhois || $(SUDO) yum install -y jwhois || :
	# for Cassandra's Python driver
	rpm -q python-setuptools python-pip python-devel libev libev-devel libsnappy-devel || $(SUDO) yum install -y python-setuptools python-pip python-devel libev libev-devel libsnappy-devel || :


# Net::ZooKeeper must be done separately due to the C library dependency it fails when attempting to install directly from CPAN. You will also need Net::ZooKeeper for check_zookeeper_znode.pl to be, see README.md or instructions at https://github.com/harisekhon/nagios-plugins
ZOOKEEPER_VERSION = 3.4.6
.PHONY: zookeeper
zookeeper:
	[ -f zookeeper-$(ZOOKEEPER_VERSION).tar.gz ] || wget -O zookeeper-$(ZOOKEEPER_VERSION).tar.gz http://www.mirrorservice.org/sites/ftp.apache.org/zookeeper/zookeeper-$(ZOOKEEPER_VERSION)/zookeeper-$(ZOOKEEPER_VERSION).tar.gz
	[ -d zookeeper-$(ZOOKEEPER_VERSION) ] || tar zxvf zookeeper-$(ZOOKEEPER_VERSION).tar.gz
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				./configure
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				make
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				$(SUDO) make install
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	perl Makefile.PL --zookeeper-include=/usr/local/include/zookeeper --zookeeper-lib=/usr/local/lib
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	LD_RUN_PATH=/usr/local/lib make
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	$(SUDO) make install
	perl -e "use Net::ZooKeeper"


.PHONY: test
test:
	cd lib && make test
	# doesn't return a non-zero exit code to test
	# for x in *.pl; do perl -T -c $x; done
	# TODO: add more functional tests back in here
	tests/help.sh

.PHONY: install
install:
	@echo "No installation needed, just add '$(PWD)' to your \$$PATH and Nagios commands.cfg"

.PHONY: update
update:
	make update2
	make
	make test

.PHONY: update2
update2:
	git pull
	git submodule update

.PHONY: clean
clean:
	rm -fr zookeeper-$(ZOOKEEPER_VERSION).tar.gz zookeeper-$(ZOOKEEPER_VERSION)
