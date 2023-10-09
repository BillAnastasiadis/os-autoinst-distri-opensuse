# SUSE's openQA tests
#
# Copyright 2019 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: This test will leave the SSH interactive session, kill the SSH tunnel and destroy the public cloud instance
#
# Maintainer: QE-SAP <qe-sap@suse.de>

use base 'sles4sap_publiccloud_basetest';
use publiccloud::ssh_interactive 'select_host_console';
use publiccloud::utils;
use testapi;
use utils;

sub run {
    my ($self, $args) = @_;
    select_host_console(force => 1);
}

1;
