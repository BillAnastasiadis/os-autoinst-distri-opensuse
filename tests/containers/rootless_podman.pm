# SUSE's openQA tests
#
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Test rootless mode on podman.
# - add a user on the /etc/subuid and /etc/subgid to allow automatically allocation subuid and subgid ranges.
# - check uids allocated to user (inside the container are mapped on the host)
# - give read access to the SUSE Customer Center credentials to call zypper from in the container.
#   This grants the current user the required access rights
# - Test rootless container:
#   * container is launched with default root user
#   * container is launched with existing user id
#   * container is launched with keep-id of the user who run the container
# - Restore /etc/zypp/credentials.d/ credentials
# Maintainer: qa-c team <qa-c@suse.de>

use Mojo::Base 'containers::basetest';
use testapi;
use serial_terminal 'select_serial_terminal';
use utils;
use containers::common;
use containers::container_images;
use containers::utils qw(registry_url get_podman_version);
use version_utils qw(is_sle is_leap is_jeos is_transactional package_version_cmp);
use power_action_utils 'power_action';
use bootloader_setup 'add_grub_cmdline_settings';
use Utils::Architectures;
use transactional 'process_reboot';
use Utils::Logging 'save_and_upload_log';

my $bsc1200623 = 0;    # to prevent printing the soft-failure more than once
my $podman_version;

sub run {
    my ($self) = @_;
    select_serial_terminal;
    my $user = $testapi::username;

    my $podman = $self->containers_factory('podman');

    # add testuser to systemd-journal group to allow non-root
    # user to access container logs via journald event driver
    # to avoid flakes w/ Podman <=4.0.0
    $podman_version = get_podman_version();
    if (package_version_cmp($podman_version, '4.0.0') <= 0) {
        assert_script_run "usermod -a -G systemd-journal $testapi::username";
    }

    if (get_var('TDUP')) {
        my $unresolved_config = script_output('rpmconfigcheck');
        my $cont_storage = '/etc/containers/storage.conf';
        if ($unresolved_config =~ m|$cont_storage|) {
            assert_script_run(sprintf('mv  %s.rpmnew %s', $cont_storage, $cont_storage));
            assert_script_run('podman system reset -f');
        }
    }

    # Prepare for Podman 3.4.4 and CGroups v2
    if (is_sle('15-SP3+') || is_leap('15.3+')) {
        record_info 'cgroup v2', 'Switching to cgroup v2';
        assert_script_run "usermod -a -G systemd-journal $testapi::username";
        if (is_transactional) {
            add_grub_cmdline_settings('systemd.unified_cgroup_hierarchy=1', update_grub => 0);
            assert_script_run('transactional-update grub.cfg');
            process_reboot(trigger => 1);
        } else {
            add_grub_cmdline_settings('systemd.unified_cgroup_hierarchy=1', update_grub => 1);
            power_action('reboot', textmode => 1);
            $self->wait_boot(bootloader_time => 360);
        }
        select_serial_terminal;

        validate_script_output 'cat /proc/cmdline', sub { /systemd\.unified_cgroup_hierarchy=1/ };
        validate_script_output 'podman info', sub { /cgroupVersion: v2/ };
        validate_script_output "id $testapi::username", sub { /systemd-journal/ };
    }

    # Check for bsc#1192051
    # Test needs to pass, if seccomp filtering is off
    assert_script_run('podman run --security-opt=seccomp=unconfined --rm -it registry.opensuse.org/opensuse/tumbleweed:latest bash -c "test -x /bin/sh"');
    # And this one is the actual check for bsc#1192051, with seccomp filtering on
    assert_script_run('podman run --rm -it registry.opensuse.org/opensuse/tumbleweed:latest bash -c "test -x /bin/sh"', fail_message => "bsc#1192051 - Permission denied for faccessat2");

    my $image = 'registry.opensuse.org/opensuse/tumbleweed:latest';

    # Some products don't have bernhard pre-defined (e.g. SLE Micro)
    if (script_run("grep $user /etc/passwd") != 0) {
        assert_script_run "useradd -m $user";
        assert_script_run "echo '$user:$testapi::password' | chpasswd";
        # Make sure user has access to tty group
        my $serial_group = script_output "stat -c %G /dev/$testapi::serialdev";
        assert_script_run "grep '^${serial_group}:.*:${user}\$' /etc/group || (chown $user /dev/$testapi::serialdev && gpasswd -a $user $serial_group)";
    }

    my $subuid_start = get_user_subuid($user);
    if ($subuid_start eq '') {
        record_soft_failure 'bsc#1185342 - YaST does not set up subuids/-gids for users';
        $subuid_start = 200000;
        my $subuid_range = $subuid_start + 1000;
        assert_script_run "usermod --add-subuids $subuid_start-$subuid_range --add-subgids $subuid_start-$subuid_range $user";
    }
    assert_script_run "grep $user /etc/subuid", fail_message => "subuid range not assigned for $user";
    assert_script_run "grep $user /etc/subgid", fail_message => "subgid range not assigned for $user";
    assert_script_run "setfacl -m u:$user:r /etc/zypp/credentials.d/*" if is_sle;

    # Remove all previous commands generated by root. Some of these commands will be triggered
    # by the rootless user and will generate the same file /tmp/scriptX which will fail if it
    # already exists owned by root
    assert_script_run 'rm -rf /tmp/script*';
    ensure_serialdev_permissions;
    select_console "user-console";

    # By default the storage driver is set to btrfs if /var is in btrfs
    # but if the home partition is not btrfs podman commands will fail with
    # Error: "/home/bernhard/.local/share/containers/storage/btrfs" is not on a btrfs filesystem
    my $storage = $podman->get_storage_driver();
    if ($storage ne 'overlay') {
        die "Unexpected storage driver -> $storage";
    }
    $podman->info();

    test_container_image(image => $image, runtime => $podman);
    build_and_run_image(base => $image, runtime => $podman);
    test_zypper_on_container($podman, $image);
    verify_userid_on_container($image, $subuid_start);
    $podman->cleanup_system_host(!$bsc1200623);
}

sub get_user_subuid {
    my ($user) = shift;
    my $start_range = script_output("awk -F':' '\$1 == \"$user\" {print \$2}' /etc/subuid",
        proceed_on_failure => 1);
    return $start_range;
}

sub verify_userid_on_container {
    my ($image, $start_id) = @_;
    my $huser_id = script_output "echo \$UID";
    record_info "host uid", "$huser_id";
    record_info "root default user", "rootless mode process runs with the default container user(root)";
    my $cid = script_output "podman run -d --rm --name test1 $image sleep infinity";
    $cid = check_bsc1200623($cid);
    validate_script_output "podman top $cid user huser", sub { /root\s+1000/ };
    validate_script_output "podman top $cid capeff", sub { /setuid/i };

    record_info "non-root user", "process runs under the range of subuids assigned for regular user";
    $cid = script_output "podman run -d --rm --name test2 --user 1000 $image sleep infinity";
    $cid = check_bsc1200623($cid);
    my $id = $start_id + $huser_id - 1;

    # podman >= v4.4.0 lists username instead of uid
    # when using `user` descriptor with `podman top`, handle
    # conditionally.
    # https://github.com/os-autoinst/os-autoinst-distri-opensuse/pull/16567
    my $huser_name = $testapi::username;
    validate_script_output "podman top $cid user huser", sub { /${huser_name}\s+${id}|1000\s+${id}/ };
    validate_script_output "podman top $cid capeff", sub { /none/ };

    record_info "root with keep-id", "the default user(root) starts process with the same uid as host user";
    $cid = script_output "podman run -d --rm --userns keep-id $image sleep infinity";
    $cid = check_bsc1200623($cid);
    # Remove once the softfail removed. it is just checks the user's mapped uid
    validate_script_output "podman exec -it $cid cat /proc/self/uid_map", sub { /1000/ };
    # Check for bsc#1182428
    # podman 2.1.1 with keep-id option list unexpected capabilities
    # podman of the same version can still show the nsenter original issue
    my $buggy_podman = (package_version_cmp($podman_version, '2.1.1') == 0);

    if ($buggy_podman && (is_aarch64 || is_s390x)) {
        my $output = script_output("podman top $cid user huser 2>&1", proceed_on_failure => 1);
        if ($output =~ "error executing .*nsenter.*executable file not found") {
            record_soft_failure "bsc#1182428 - Issue with nsenter from podman-top";
        }
    } else {
        validate_script_output "podman top $cid user huser", sub { /bernhard\s+bernhard/ };
        my $output = script_output "podman top $cid capeff";

        if ($output !~ /none/) {
            if ($buggy_podman) {
                record_soft_failure "bsc#1182428 - Issue with nsenter from podman-top";
            } else {
                die "Test does not expect to list any container capabilities";
            }
        }
    }


    ## Check if uid change within the container works as desired
    # Note: If this part with 'zypper install' becomes cumbersome we could switch to an image, which already includes sudo and useradd
    my $cmd = '(id | grep uid=0) && zypper -n -q in sudo shadow && useradd geeko -u 1000 && (sudo -u geeko id | grep geeko)';
    script_retry("podman run -ti --rm '$image' bash -c '$cmd'", timeout => 300, retry => 3, delay => 60);

}

sub check_bsc1200623() {
    my ($cid) = shift;
    # When this bug appears, the output (cid) is composed of 2 lines, e.g.
    # cid = "
    # 2022-07-05T08:48:56.151176-04:00 susetest systemd[3438]: Failed to start podman-6734.scope.
    # 5b08b0dc136dd32bb30e69e4deb5df511dea0602d6b0c8d3623120370184506a"
    # So, we need to remove the first one.
    if ($cid =~ /Failed to start podman/) {
        record_soft_failure('bsc#1200623 - systemd[3557]: Failed to start podman-3627.scope') unless ($bsc1200623);
        $bsc1200623 = 1;    # to prevent printing the soft-failure more than once
        ($cid) =~ s/.*\n//;
    }
    return $cid;
}

sub post_run_hook {
    my $self = shift;
    select_serial_terminal();
    assert_script_run "setfacl -x u:$testapi::username /etc/zypp/credentials.d/*" if is_sle;
    $self->SUPER::post_run_hook;
}

sub post_fail_hook {
    my $self = shift;
    save_and_upload_log('cat /etc/{subuid,subgid}', "/tmp/permissions.txt");
    assert_script_run("tar -capf /tmp/proc_files.tar.xz /proc/self");
    upload_logs("/tmp/proc_files.tar.xz");
    if (is_sle) {
        save_and_upload_log('ls -la /etc/zypp/credentials.d', "/tmp/credentials.d.perm.txt");
        assert_script_run "setfacl -x u:$testapi::username /etc/zypp/credentials.d/*";
    }
    $self->SUPER::post_fail_hook;
}

1;
