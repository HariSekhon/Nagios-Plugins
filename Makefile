#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#

export PATH := $(PATH):/usr/local/bin

CPANM = cpanm

ifdef PERLBREW_PERL
	SUDO2 =
else
	SUDO2 = sudo
endif

ifdef VIRTUAL_ENV
	SUDO3 =
# Travis has custom python install earlier in $PATH even in Perl builds so need to install PyPI modules locally to non-system python otherwise they're not found by programs.
# Perms not set correctly on custom python install in Travis perl build so workaround is done to chown to travis user in .travis.yml
# Better than modifying $PATH to put /usr/bin first which is likely to affect many other things including potentially not finding the perlbrew installation first
else ifdef TRAVIS
	SUDO3 =
else
	SUDO3 = sudo -H
endif

# EUID /  UID not exported in Make
# USER not populated in Docker
ifeq '$(shell id -u)' '0'
	SUDO =
	SUDO2 =
	SUDO3 =
else
	SUDO = sudo
endif

.PHONY: build
# space here prevents weird validation warning from check_makefile.sh => Makefile:40: warning: undefined variable `D'
build :
	if [ -x /sbin/apk ];        then make apk-packages; fi
	if [ -x /usr/bin/apt-get ]; then make apt-packages; fi
	if [ -x /usr/bin/yum ];     then make yum-packages; fi
	
	git submodule init
	git submodule update --recursive

	cd lib && make
	cd pylib && make

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
	#
	which cpanm || { yes "" | $(SUDO2) cpan App::cpanminus; }
	yes "" | $(SUDO2) $(CPANM) --notest \
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
		Digest::Adler32 \
		Digest::CRC \
		Digest::MD5 \
		Digest::SHA \
		Digest::SHA1 \
		Exporter::Tiny \
		ExtUtils::Config \
		ExtUtils::Constant \
		ExtUtils::Helpers \
		ExtUtils::InstallPaths \
		IO::Pty \
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
		Net::DNS@1.05 \
		Net::LDAP \
		Net::LDAPI \
		Net::LDAPS \
		Net::SSH::Expect \
		Readonly \
		Readonly::XS \
		Search::Elasticsearch \
		SMS::AQL \
		Socket6 \
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
		;
	# downgrading Net::DNS as a workaround for taint mode bug:
	# https://rt.cpan.org/Public/Bug/Display.html?id=114819
	#$(SUDO2) $(CPANM) --notest Net::DNS@1.05 \
	#
	# newer versions of the Redis module require Perl >= 5.10, this will install the older compatible version for RHEL5/CentOS5 servers still running Perl 5.8 if the latest module fails
	# the backdated version might not be the perfect version, found by digging around in the git repo
	$(SUDO2) $(CPANM) --notest Redis || $(SUDO2) $(CPANM) --notest DAMS/Redis-1.976.tar.gz

		#Net::Async::CassandraCQL \

	# Fix for Kafka dependency bug in NetAddr::IP::InetBase
	libfilepath=`perl -MNetAddr::IP::InetBase -e 'print $$INC{"NetAddr/IP/InetBase.pm"}'`; grep -q 'use Socket' $$libfilepath || $(SUDO2) sed -i.bak "s/use strict;/use strict; use Socket;/" $$libfilepath

	# newer version of setuptools (>=0.9.6) is needed to install cassandra-driver
	# might need to specify /usr/bin/easy_install or make /usr/bin first in path as sometimes there are version conflicts with Python's easy_install
	$(SUDO) easy_install -U setuptools || $(SUDO3) easy_install -U setuptools || :
	$(SUDO) easy_install pip || :
	# cassandra-driver is needed for check_cassandra_write.py + check_cassandra_query.py
	# upgrade required to get install to work properly on Debian
	$(SUDO) pip install --upgrade pip
	$(SUDO3) pip install -r requirements.txt
	# in requirements.txt now
	#$(SUDO3) pip install cassandra-driver scales blist lz4 python-snappy
	# prevents https://urllib3.readthedocs.io/en/latest/security.html#insecureplatformwarning
	$(SUDO3) pip install --upgrade ndg-httpsclient
	#. tests/utils.sh; $(SUDO) $$perl couchbase-csdk-setup
	#$(SUDO3) pip install couchbase
	
	# install MySQLdb python module for check_logserver.py / check_syslog_mysql.py
	# fails if MySQL isn't installed locally
	$(SUDO3) pip install MySQL-python
	@echo
	#make jar-plugins
	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins)"

.PHONY: apk-packages
apk-packages:
	$(SUDO) apk update
	$(SUDO) apk add alpine-sdk
	$(SUDO) apk add bash
	$(SUDO) apk add expat-dev
	$(SUDO) apk add gcc
	$(SUDO) apk add git
	$(SUDO) apk add libxml2-dev
	$(SUDO) apk add make
	$(SUDO) apk add mariadb-dev
	$(SUDO) apk add openssl-dev
	$(SUDO) apk add perl
	$(SUDO) apk add perl-dev
	$(SUDO) apk add py-mysqldb
	$(SUDO) apk add py-pip
	$(SUDO) apk add ruby
	$(SUDO) apk add wget

.PHONY: apk-packages-remove
apk-packages-remove:
	cd lib && make apk-packages-remove
	$(SUDO) apk del alpine-sdk
	$(SUDO) apk del expat-dev
	$(SUDO) apk del libxml2-dev
	$(SUDO) apk del mariadb-dev
	$(SUDO) apk del openssl-dev
	$(SUDO) apk del perl-dev
	$(SUDO) apk del wget

.PHONY: apt-packages
apt-packages:
	$(SUDO) apt-get update
	# needed to fetch and build CPAN modules and fetch the library submodule at end of build
	$(SUDO) apt-get install -y build-essential
	$(SUDO) apt-get install -y libwww-perl
	$(SUDO) apt-get install -y git
	$(SUDO) apt-get install -y wget
	# for DBD::mysql as well as headers to build DBD::mysql if building from CPAN
	$(SUDO) apt-get install -y libdbd-mysql-perl
	$(SUDO) apt-get install -y libmysqlclient-dev
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	$(SUDO) apt-get install -y libssl-dev
	$(SUDO) apt-get install -y libsasl2-dev
	# for XML::Simple building
	$(SUDO) apt-get install -y libexpat1-dev
	# for ndg-httpsclient
	$(SUDO) apt-get install -y python-pyasn1
	# Class::Accessor pre-packaged
	#$(SUDO) apt-get install libclass-accessor-perl
	# for check_whois.pl - looks like this has been removed from repos :-/
	$(SUDO) apt-get install -y jwhois || :
	# for LWP::Authenticate
	#apt-get install -y krb5-config # prompts for realm + KDC, use libkrb5-dev instead
	$(SUDO) apt-get install -y libkrb5-dev
	# for Cassandra's Python driver
	$(SUDO) apt-get install -y python-setuptools
	$(SUDO) apt-get install -y python-pip
	$(SUDO) apt-get install -y python-dev
	$(SUDO) apt-get install -y libev4
	$(SUDO) apt-get install -y libev-dev
	$(SUDO) apt-get install -y libsnappy-dev
	# needed for ndg-httpsclient upgrade
	$(SUDO) apt-get install -y libffi-dev

.PHONY: apt-packages-remove
apt-packages-remove:
	cd lib && make apt-packages-remove
	$(SUDO) apt-get install -y build-essential
	$(SUDO) apt-get install -y wget
	$(SUDO) apt-get install -y libmysqlclient-dev
	$(SUDO) apt-get install -y libssl-dev
	$(SUDO) apt-get install -y libsasl2-dev
	$(SUDO) apt-get install -y libexpat1-dev
	$(SUDO) apt-get install -y libkrb5-dev
	$(SUDO) apt-get install -y python-dev
	$(SUDO) apt-get install -y libev-dev
	$(SUDO) apt-get install -y libsnappy-dev
	$(SUDO) apt-get install -y libffi-dev

.PHONY: yum-packages
yum-packages:
	rpm -q gcc               || $(SUDO) yum install -y gcc
	rpm -q gcc-c++           || $(SUDO) yum install -y gcc-c++
	rpm -q perl-CPAN         || $(SUDO) yum install -y perl-CPAN
	rpm -q perl-libwww-perl  || $(SUDO) yum install -y perl-libwww-perl
	# to fetch and untar ZooKeeper, plus wget epel rpm
	rpm -q wget              || $(SUDO) yum install -y wget
	rpm -q tar               || $(SUDO) yum install -y tar
	rpm -q which             || $(SUDO) yum install -y which
	# to build DBD::mysql if building from CPAN
	rpm -q mysql-devel 		 || $(SUDO) yum install -y mysql-devel
	rpm -q perl-DBD-MySQL    || $(SUDO) yum install -y perl-DBD-MySQL
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	rpm -q openssl-devel     || $(SUDO) yum install -y openssl-devel
	# for XML::Simple building
	rpm -q expat-devel       || $(SUDO) yum install -y expat-devel
	# for ndg-httpsclient
	rpm -q python-pyasn1     || $(SUDO) yum install -y python-pyasn1
	# for Cassandra's Python driver
	# python-pip requires EPEL, so try to get the correct EPEL rpm
	# this doesn't work for some reason CentOS 5 gives 'error: skipping https://dl.fedoraproject.org/pub/epel/epel-release-latest-5.noarch.rpm - transfer failed - Unknown or unexpected error'
	# must instead do wget 
	rpm -q epel-release      || yum install -y epel-release || { wget -t 100 --retry-connrefused -O /tmp/epel.rpm "https://dl.fedoraproject.org/pub/epel/epel-release-latest-`grep -o '[[:digit:]]' /etc/*release | head -n1`.noarch.rpm" && $(SUDO) rpm -ivh /tmp/epel.rpm && rm -f /tmp/epel.rpm; }
	# for check_whois.pl
	rpm -q jwhois            || $(SUDO) yum install -y jwhois
	# only available on EPEL in CentOS 5
	rpm -q git               || $(SUDO) yum install -y git
	rpm -q python-setuptools || $(SUDO) yum install -y python-setuptools
	rpm -q python-pip        || $(SUDO) yum install -y python-pip
	rpm -q python-devel      || $(SUDO) yum install -y python-devel
	rpm -q libev             || $(SUDO) yum install -y libev
	rpm -q libev-devel       || $(SUDO) yum install -y libev-devel
	rpm -q snappy-devel      || $(SUDO) yum install -y snappy-devel
	# needed for ndg-httpsclient upgrade
	rpm -q libffi-devel	     || $(SUDO) yum install -y libffi-devel
	# needed to build pyhs2
	# libgsasl-devel saslwrapper-devel
	rpm -q cyrus-sasl-devel  || $(SUDO) yum install -y cyrus-sasl-devel
	# for check_yum.pl / check_yum.py
	rpm -q yum-security yum-plugin-security || yum install -y yum-security yum-plugin-security

.PHONY: yum-packages-remove
yum-packages-remove:
	cd lib && make yum-packages-remove
	rpm -q gcc              && $(SUDO) yum remove -y gcc
	rpm -q gcc-c++          && $(SUDO) yum remove -y gcc-c++
	rpm -q perl-CPAN        && $(SUDO) yum remove -y perl-CPAN
	rpm -q mysql-devel      && $(SUDO) yum remove -y mysql-devel
	rpm -q openssl-devel    && $(SUDO) yum remove -y openssl-devel
	rpm -q expat-devel      && $(SUDO) yum remove -y expat-devel
	rpm -q python-devel     && $(SUDO) yum remove -y python-devel
	rpm -q libev-devel      && $(SUDO) yum remove -y libev-devel
	rpm -q snappy-devel     && $(SUDO) yum remove -y snappy-devel
	rpm -q libffi-devel     && $(SUDO) yum remove -y libffi-devel
	rpm -q cyrus-sasl-devel && $(SUDO) yum remove -y cyrus-sasl-devel

# Net::ZooKeeper must be done separately due to the C library dependency it fails when attempting to install directly from CPAN. You will also need Net::ZooKeeper for check_zookeeper_znode.pl to be, see README.md or instructions at https://github.com/harisekhon/nagios-plugins
# doesn't build on Mac < 3.4.7 / 3.5.1 / 3.6.0 but the others are in the public mirrors yet
# https://issues.apache.org/jira/browse/ZOOKEEPER-2049
ZOOKEEPER_VERSION = 3.4.8
.PHONY: zookeeper
zookeeper:
	[ -x /sbin/apk ]        && make apk-packages || :
	[ -x /usr/bin/apt-get ] && make apt-packages || :
	[ -x /usr/bin/yum ]     && make yum-packages || :
	[ -f zookeeper-$(ZOOKEEPER_VERSION).tar.gz ] || wget -t 100 --retry-connrefused -O zookeeper-$(ZOOKEEPER_VERSION).tar.gz "http://www.apache.org/dyn/closer.lua?filename=zookeeper/zookeeper-${ZOOKEEPER_VERSION}/zookeeper-${ZOOKEEPER_VERSION}.tar.gz&action=download"
	[ -d zookeeper-$(ZOOKEEPER_VERSION) ] || tar zxf zookeeper-$(ZOOKEEPER_VERSION).tar.gz
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				./configure
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				make
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				$(SUDO) make install
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	perl Makefile.PL --zookeeper-include=/usr/local/include --zookeeper-lib=/usr/local/lib
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	LD_RUN_PATH=/usr/local/lib $(SUDO) make
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	$(SUDO) make install
	perl -e "use Net::ZooKeeper"

.PHONY: jar-plugins
jar-plugins:
	@echo Fetching pre-compiled Java / Scala plugins
	@echo
	@echo Fetching Kafka Scala Nagios Plugin
	wget -c -t 100 --retry-connrefused https://github.com/HariSekhon/nagios-plugin-kafka/blob/latest/check_kafka
	wget -c -t 100 --retry-connrefused https://github.com/HariSekhon/nagios-plugin-kafka/releases/download/latest/check_kafka.jar

.PHONY: sonar
sonar:
	sonar-scanner

.PHONY: test
test:
	cd lib && make test
	rm -fr lib/cover_db || :
	cd pylib && make test
	tests/all.sh

.PHONY: install
install:
	@echo "No installation needed, just add '$(PWD)' to your \$$PATH and Nagios commands.cfg"

.PHONY: update
update:
	@make update2
	@make

.PHONY: update2
update2:
	make update-no-recompile

.PHONY: update-no-recompile
update-no-recompile:
	git pull
	git submodule update --init --recursive

.PHONY: update-submodules
update-submodules:
	git submodule update --init --remote
.PHONY: updatem
updatem:
	make update-submodules

.PHONY: clean
clean:
	cd lib && make clean
	cd pylib && make clean
	@find . -maxdepth 3 -iname '*.py[co]' -o -iname '*.jy[co]' | xargs rm -f || :
	@make clean-zookeeper
	rm -fr tests/spark-*-bin-hadoop*

.PHONY: clean-zookeeper
clean-zookeeper:
	rm -fr zookeeper-$(ZOOKEEPER_VERSION).tar.gz zookeeper-$(ZOOKEEPER_VERSION)
