# SUSE's openQA tests
#
# Copyright © 2019 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Test common commands: modinfo, lsmod, modprobe, rmmod,
# depmod. Tests the commands and their output for common words that
# should appear independently of the individual modules loaded in
# each system.
# * modinfo: 'filename ... .ko', 'license: ...', 'depends: ...'
# * lsmod: 'Module', 'Size', 'Used by'
# * modprobe: We make sure a random module is not active and then we activate it
# * rmmod: We check the exit status and then we enable the disabled module again
# * depmod: 'lib/modules', '.ko', 'kernel'.
# Maintainer: Vasilios Anastasiadis <vasilios.anastasiadis@suse.com>

use base "consoletest";
use strict;
use warnings;
use testapi;
use utils 'zypper_call';

sub run {
    select_console 'root-console';
    #get list of loadable modules on the system
    my $nm = script_output("find /lib/modules/\$(uname -r) -type f -name '*.ko'");
    #take the last module, strip it of unnecesary characters and extensions
    my @full = split '/', $nm;
    my $wrd = $full[-1];
    my @mdl = split '\.', $wrd; #mdl[0] contains a loadable module

    #test modinfo command
    assert_script_run("OUT=\"\$(modinfo $mdl[0])\"");
    #test the output for common words that should always appear
    assert_script_run('grep -o -m 1 \'^filename:.*.ko\' <<< "$OUT"');
    assert_script_run('grep -o -m 1 \'^license:.*\' <<< "$OUT"');
    assert_script_run('grep -o -m 1 \'^depends:.*\' <<< "$OUT"');

    #test lsmod command
    #test that the output has the expected correct format
    assert_script_run('lsmod | grep \'^Module.*Size.*Used by$\'');

    #test modprobe -v command
    script_run("rmmod $mdl[0]");
    assert_script_run("modprobe -v --allow-unsupported-modules $mdl[0] | grep '^insmod.*$mdl[0].ko'");

    #test rmmod command
    assert_script_run("rmmod $mdl[0]");
    #make sure the command terminated the module by starting it again
    assert_script_run("modprobe -v --allow-unsupported-modules $mdl[0] | grep '^insmod.*$mdl[0].ko'");

    #test depmod command
    assert_script_run('OUT="$(depmod -av)"');
    #test the output for common words that should always appear
    assert_script_run('grep -o -m 1 .ko <<< "$OUT"');
    assert_script_run('grep -o -m 1 lib/modules <<< "$OUT"');
    assert_script_run('grep -o -m 1 kernel <<< "$OUT"');
}

1;
