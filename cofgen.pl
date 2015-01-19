#!/usr/bin/perl
#
# cofgen - Config Generator
#
# Simple script to generate configuration for network gear.
#
# Copyright (C) 2013-2014  Petr Havlicek (ph@petrh.cz)
#
#	This program is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 3 of the License, or
#	any later version.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program.  If not, see <http://www.gnu.org/licenses/>.

use 5.010;
use strict;
use warnings;

use Getopt::Std;
use Data::Dumper;
use XML::LibXML::Simple;
use List::MoreUtils qw(uniq);

use vars qw($PROGNAME $VERSION);
use vars qw( $opt_c $opt_d );

$PROGNAME = 'cofgen';
$VERSION  = '0.1';

# End program after printing version or help
$Getopt::Std::STANDARD_HELP_VERSION = "TRUE";

# Process argumets
getopts('c:d:');

# Load file with configuration
my $config_file = "sample_config.xml";
$config_file = $opt_c if defined $opt_c;
die "File $config_file don't exist!"
  unless -e $config_file;

# Load device list
my $device_file = "sample_device.xml";
$device_file = $opt_d if defined $opt_d;
die "File $device_file don't exist!"
  unless -e $device_file;

# Parse device list
my $device_list = XMLin(
    $device_file,
    KeyAttr    => [ 'name' ],
) or die "Cannot parse config!";
$device_list = $device_list->{'device'};


# Parse config file
my $config_snipps = XMLin(
    $config_file,
    KeyAttr    => [ 'type' ],
    ContentKey => '-config'
) or die "Cannot parse config!";

# Make direcotry for results
my $output_dir = "output";
$output_dir = $ARGV[0] if $ARGV[0];
mkdir $output_dir;
chdir $output_dir;

my $string_to_write = "";

# Per device loop
for (keys $device_list) {
    # Prepare value for substitution
    my $ip = $device_list->{$_}->{'ip'};
    # Get vlan list
    my @acc_vlans;
    for ( $device_list->{$_}->{int} ) {
        my $ints = $_;
        for ( keys $ints ) {
            if ( $ints->{$_}->{'type'} eq 'access' ) {
                push @acc_vlans, $ints->{$_}->{'vlan'};
            }
        }
    }
    @acc_vlans = uniq( sort ( @acc_vlans ));
    my $acc_vlan_str = join ( ',' , @acc_vlans );

    open (CFG_FILE, ">$_.cfg");

    # Start of configuration
    my $string_to_write = $config_snipps->{'device'}->{"start"};
    $string_to_write =~ s/:HOSTNAME:/$_/g;
    $string_to_write =~ s/:INSPETCT_VLAN:/$acc_vlan_str/g;
    print CFG_FILE $string_to_write;

    for ( $device_list->{$_}->{int} ) {
        my $ints = $_;
        for ( keys $ints ) {
            my $selected = $_;
            # Expanding ranges
            if ( /(.*)\/(\d+)-(\d+)/ ) {
                my $prefix      = $1;
                my $start_port  = $2;
                my $end_port    = $3;

                for (my $i = $start_port ; $i <= $end_port; $i++ ) {
                    my $port = "$prefix/$i";
                    $ints->{$port} = $ints->{$selected};
                }
                delete $ints->{$selected};
            }

        }
    }

    # Gen config for interface
    for ( $device_list->{$_}->{int} ) {
        my $ints = $_;
        for ( sort { expand($a) cmp expand($b) } keys $ints ) {
            my $int = $_;
            my $desc = $ints->{$_}->{'desc'};

            # Access
            if ( $ints->{$_}->{'type'} eq 'access' ) {
                my $vlan = $ints->{$_}->{'vlan'};
                my $string_to_write = $config_snipps->{'port'}->{"access"};

                $string_to_write =~ s/:INT:/$int/g;
                $string_to_write =~ s/:DESC:/$desc/g;
                $string_to_write =~ s/:ACC_VLAN:/$vlan/g;
                print CFG_FILE $string_to_write;
            }
            # Trunk
            # TODO Validate Allowed_VLAN against access vlans
            if ( $ints->{$_}->{'type'} eq 'trunk' ) {
                my $allowed_vlan = $ints->{$_}->{'allowed_vlan'};
                my $string_to_write = $config_snipps->{'port'}->{"trunk"};
                $string_to_write =~ s/:INT:/$int/g;
                $string_to_write =~ s/:DESC:/$desc/g;
                $string_to_write =~ s/:ALLOWED_VLAN:/$allowed_vlan/g;
                print CFG_FILE $string_to_write;
            }
            # Unused
            # TODO Set unused port dynamiclly based on used one
            if ( $ints->{$_}->{'type'} eq 'unused' ) {
                my $allowed_vlan = $ints->{$_}->{'allowed_vlan'};
                my $string_to_write = $config_snipps->{'port'}->{"unused"};
                $string_to_write =~ s/:INT:/$int/g;
                print CFG_FILE $string_to_write;
            }
        }
    }

    # End of configuration
    $string_to_write = $config_snipps->{'device'}->{"end"};
    $string_to_write =~ s/:MGMT_IP:/$ip/g;
    print CFG_FILE $string_to_write;
    close (CFG_FILE);
}

exit;

sub expand {
    my $int = shift;
    $int =~ /\/(\d+)$/;
    if ( $1 < 10 ) {
        $int =~ s/(\d)$/0$1/;
    }
    return $int;
}

sub VERSION_MESSAGE {
    print "$PROGNAME version $VERSION.\n"
      . "  by Petr Havlicek (ph\@petrh.cz)\n\n";
}

# Help message for Getopt::Std
sub HELP_MESSAGE {
    print "USAGE:  [-c <CONFIG>] [-d <DEVICE>] DIRECTORY\n\n"
      . "\tCONFIG - filename with config XML. (config.xml by default)\n"
      . "\tDEVICE - filename device list in XML. (device.xml by default)\n"
      . "\tDIRECOTRY - directory name for generated config\n\n";
}
