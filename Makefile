#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#

.PHONY: install
install:
	@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	@# putting modules one per line just for easy of maintenance
	cpan Data::Dumper \
     DBD::mysql \
	 DBI \
	 JSON \
	 JSON:XS \
	 LWP::Simple \
	 LWP::UserAgent \
	 Net::DNS \
	 Net::SSH::Expect \
	 Thrift \
	 Time::HiRes \
	 SMS::AQL
	git submodule init
	git submodule update
