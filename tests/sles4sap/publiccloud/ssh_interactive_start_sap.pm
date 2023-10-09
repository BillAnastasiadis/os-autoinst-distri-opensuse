# SUSE's openQA tests
#
# Copyright 2019-2022 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: openssh
# Summary: This tests will establish the tunnel and enable the SSH interactive console
#
# Maintainer: QE-SAP <qe-sap@suse.de>

use base 'sles4sap_publiccloud_basetest';
use testapi;
use serial_terminal 'select_serial_terminal';
use utils;
use publiccloud::ssh_interactive qw(ssh_interactive_start);
use publiccloud::utils qw(allow_openqa_port_selinux);
use version_utils;

sub run {
    my ($self, $args) = @_;
    ssh_interactive_start($args);
}

sub test_flags {
    return {fatal => 1, publiccloud_multi_module => 1};
}

1;
