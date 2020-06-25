#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

BEGIN {
    if (!exists $ENV{PLERD_HOME}) {
        $ENV{PLERD_HOME} = "$FindBin::Bin/..";
    }
}

Main();
exit;

# @todo: when a test fails, it should return a failed exit code
# This should detect that, run the other tests, but also exit 
# with an error code.
sub Main {
    my $failed = 0;
    for my $file (@ARGV) {
        if (-e $file) {
            my @cmd = ($^X, $file);
            print "Running: $file\n";

            system(@cmd);
            my $exit_code = $? >> 8;
            $failed = 1 if $exit_code != 0;

            if ($? == -1) {
                die("Failed to execute: ", join(" ", @cmd));
                $failed = 1;
            } elsif ($? & 127) {
                die(
                    sprintf("Died with signal: %d", ($? & 127))
                );
            }
        }
    }

    if ($failed) {
        exit(1);
    }
}