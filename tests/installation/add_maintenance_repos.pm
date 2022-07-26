# SUSE's openQA tests
#
# Copyright 2022 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Add new add-ons using maintenance test repo URLs.
#
# Maintainer: QA SLE YaST team <qa-sle-yast@suse.de>

use base 'y2_installbase';
use strict;
use warnings;
use testapi 'get_var';

sub run {
    set_var('MAINT_TEST_REPO', get_var('INCIDENT_REPO')) if get_var('INCIDENT_REPO');
    my @repos = split(/,/, get_var('MAINT_TEST_REPO'));

    $testapi::distri->get_add_on_product()->confirm_like_additional_add_on();

    while (defined(my $maintrepo = shift @repos)) {     
        $testapi::distri->get_add_on_product()->accept_current_media_type_selection();
        $testapi::distri->get_repository_url()->add_repo({url => $maintrepo});
        if (@repos) {
            $testapi::distri->get_add_on_product_installation()->add_add_on_product();
        }
    }
    $testapi::distri->get_add_on_product_installation()->accept_add_on_products();
}

1;
