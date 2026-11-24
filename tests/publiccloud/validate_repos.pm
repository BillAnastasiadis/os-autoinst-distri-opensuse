# SUSE's openQA tests
#
# Copyright 2019-2021 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Download repositores from the internal server
#
# Maintainer: QE-C team <qa-c@suse.de>

use Mojo::Base 'consoletest';
use registration;
use testapi;
use utils;
use qam;
use publiccloud::ssh_interactive "select_host_console";
use publiccloud::utils "validate_repo";
use sles4sap::qesap::qesapdeployment "qesap_incident_packages_in_image";

sub run {
    my ($self, $args) = @_;
    select_host_console();    # select console on the host, not the PC instance

    if (get_var('PUBLIC_CLOUD_SKIP_MU')) {
        # Skip maintenance updates. This is useful for debug runs
        record_info('Skip validation', 'Skipping maintenance update validation (triggered by setting)');
        return;
    } else {
        my @repos = get_test_repos();
        # Failsafe: Fail if there are no test repositories, otherwise we have the wrong template link
        my $count = scalar @repos;
        my $check_empty_repos = get_var('PUBLIC_CLOUD_IGNORE_EMPTY_REPO', 0) == 0;
        die "No test repositories" if ($check_empty_repos && $count == 0);

        my $repo_count = 0;
        my ($incident, $type);
        for my $maintrepo (@repos) {
            next unless validate_repo($maintrepo);
            $repo_count++;
        }
        die "No usable test repositories" if ($repo_count == 0);

        # Only with PUBLIC_CLOUD_REQUIRE_TEST_REPO_UPDATES: record which packages of the test repositories
        # are already in the image. The package data is available only for the images of the cloud catalog.
        return unless (get_var('PUBLIC_CLOUD_REQUIRE_TEST_REPO_UPDATES') && get_var('PUBLIC_CLOUD_IMAGE_ID') && !get_var('PUBLIC_CLOUD_IMAGE_LOCATION'));
        my $found = qesap_incident_packages_in_image(image => get_var('PUBLIC_CLOUD_IMAGE_ID'), repos => join(',', @repos));
        # An empty hash means that the data is available and no package is in the image: the update
        # cannot change the image, then stop here, before the deployment. post_fail_hook changes
        # the result of this module to softfail and, as the module is fatal, the next modules are skipped.
        if (ref($found) eq 'HASH' && !%$found) {
            $self->{stop_as_softfail} = 'No package of the test repositories is in the image ' . get_var('PUBLIC_CLOUD_IMAGE_ID');
            die $self->{stop_as_softfail};
        }
    }
}

sub post_fail_hook {
    my ($self) = @_;
    force_soft_failure($self->{stop_as_softfail}) if $self->{stop_as_softfail};
}

sub test_flags {
    return {
        fatal => 1,
        milestone => 1
    };
}

1;
