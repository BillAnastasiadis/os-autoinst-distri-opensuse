# SUSE's openQA tests
#
# Copyright 2019 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: zypper
# Summary: Refresh repositories, apply patches and reboot
#
# Maintainer: qa-c <qa-c@suse.de>

use strict;
use warnings;
use base 'sles4sap_publiccloud_basetest';
use testapi;
use registration;
use utils;
use publiccloud::ssh_interactive qw(select_host_console);
use publiccloud::utils qw(kill_packagekit is_azure);

sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}

sub run {
    my ($self, $run_args) = @_;
    record_info("YO", "STOP PATCHING AND REBOOTING MULTIPLE TIMES, YOU #&*&^%&");
}

1;
