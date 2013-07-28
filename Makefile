#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#

.PHONY: install
install:
	@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	# putting modules one per line just for easy of maintenance
	cpan Data::Dumper
	cpan DBD::mysql
	cpan DBI
	cpan JSON
	cpan JSON:XS
	cpan LWP::Simple
	cpan LWP::UserAgent
	cpan Net::DNS
	cpan Net::SSH::Expect
	cpan Thrift
	cpan SMS::AQL
	git submodule init
	git submodule update
