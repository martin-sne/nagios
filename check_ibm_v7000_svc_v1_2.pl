#!/usr/bin/perl  
#
# check_ibm_v7000_svc Nagios check
# you need to configure a ssh key without passphrase for logins to your V7000 storage array.
# IBM SVC.pm Perl Module is required and available here:
# https://www14.software.ibm.com/webapp/iwm/web/preLogin.do?source=AW-0NK
# http://www.alphaworks.ibm.com/tech/svctools
#
# Martin Leucht <mleucht@ipb.de> 09.01.2013
# Version 1.1
#
# fixed version 1.2 03.04.2014
#
# Usage: check_ibm_v7000_svc.pl	-cluster=[IP or hostname] -check=[check] [ -exclude=[listofitems] ]
#
# this script can check the following things of your IBM V7000 SVC
#
# lsarray -> state of array MDisks
# lsdrive -> state of drives
# lunonline / lsvdisk -> state of volumes (lun's/vdisk's)
# lsenclosure -> state of enclosures
# lsenclosurebattery -> state of batteries
# lsenclosurecanister -> state of canister/nodes
# lsenclosurepsu -> state of psu's
# lsenclosureslot -> state of port enclosure slots
# luninsync / lsrcrelationship -> state of syncs of your volumes (if you have more than one machine and mirroring)
# lsenclosureslotx -> state of enclosure slot port  
#
# TODO: ISCSI port check (BUG in Perl module - lsportip state is not provided via IBM::SVC)
#
#   example nagios command definition
#
# define command {
#    command_name    check_ibm_v7000_svc
#    command_line    $USER1$/check_ibm_v7000_svc.pl -cluster=$HOSTADDRESS$ -check=$ARG1$ -v
# }
#
#   example command excluding some items
# 
# define command {
#    command_name    check_ibm_v7000_svc_exclude
#    command_line    $USER1$/check_ibm_v7000_svc.pl -cluster=$HOSTADDRESS$ -check=$ARG1$ -exclude=$ARG2$ -v
# }
#
#   ... and service definition
# 
# define service {
#    use                             severity2,noperf
#    service_description             check_lunsonline
#    host_name                       storwize01,storwize02
#    check_command                   check_ibm_v7000_svc!lunonline!'lun1,lun2'
# }

use strict;
use IBM::SVC;
use Getopt::Long;
#use Data::Dumper;

my ($cluster, $ssh, $verbose, $keyfile, $user, $check, $help, $exclude);
$ssh="ssh";
$user="nagios";
my $state="";
my $message="";
my $params={};
my $svc_command="";
my $item="";
my $item_name="";
my $item_state="";
my $msg="";
my @exclude="";
my $x=0;
my %excl=();

GetOptions (
        "cluster=s"      => \$cluster,
        "keyfile=s"      => \$keyfile,
        "verbose|v"      => \$verbose,
        "ssh=s"          => \$ssh,
        "check=s"	     => \$check,
        "help|h"	     => \$help,
        "exclude=s"	     => \$exclude,
        "user=s"	     => \$user
); 

if ( !$cluster || !$check || $help) {
    print_usage();
    exit(0);
}
# Nagios exit states
our %states = (
        OK       => 0,
        WARNING  => 1,
        CRITICAL => 2,
        UNKNOWN  => 3
);
# Nagios state names
our %state_names = (
        0 => 'OK',
        1 => 'WARNING',
        2 => 'CRITICAL',
        3 => 'UNKNOWN'
);
# get excluded items
if ($exclude ne "") {
	if ($check eq "lunonline" || $check eq "luninsync") {
		@exclude = split(",",$exclude);
        foreach (@exclude) {
			$x++;
            $excl{$_} = $x;
		}	
	} else {
		print "excluding is only available for lunonline and luninsync check!\n";
		exit(0);
	}

}
# return states V7000 (see on console by typing svc_command -h
# generic_states for lunonline, lsenclosure,
# lsenclosurecanister, lsenclosurepsu, lsenclosureslot checks

my %generic_states = (
				'online'	=>	'OK',
				'offline'	=>	'CRITICAL',
				'degraded'	=>	'CRITICAL', );
my %luninsync_states = (	
				'consistent_synchronized'	=>	'OK',
				'consistent_copying'		=>	'OK',
				'inconsistent_stopped'		=>	'CRITICAL',
				'consistent_stopped'		=>	'WARNING',
				'idling'                    =>	'WARNING',
				'consistent_disconnected'	=>	'CRITICAL',
				'inconsistent_copying'		=>	'CRITICAL',
				'idling_disconnected'		=>	'CRITICAL',
				'inconsistent_disconnected'	=>	'CRITICAL',	);
my %lsdrive_states = (
                ''              =>      'OK',
                'offline'       =>      'CRITICAL',
                'degraded'      =>      'CRITICAL', );
my %lsarray_states = (
				'offline'			=>	'CRITICAL',
				'degraded'			=>	'CRITICAL',
				'syncing'           =>  'WARNING',
				'initting'			=>	'OK',
				'online'			=>	'OK', );
my %lsenclosureslot_states = (
				'online'                    =>   'OK',
				'excluded_by_drive'         =>	'WARNING',
				'excluded_by_enclosure'		=>	'WARNING',
				'excluded_by_system'		=>	'WARNING',);
# do not edit anything below this

sub print_usage {
        print <<EOU;

    Usage: $0 -cluster=[IP or hostname] -check=[check] -v

    -cluster          	Hostname or IP address of V7000 SVC (*required*)
    -check              Checktype (*required*)
                        Possible values are:
                        * lunonline|luninsync
                        * lsarray|lsdrive|lsenclosure|lsenclosurebattery
                        * lsenclosurecanister|lsenclosurepsu|lsenclosureslotx
                        ( lsenclosureslotx = lsenclosureslot1 ... lsenclosureslotx )
    
    -user		        Username which is configured on your v7000 (default nagios)
    -keyfile            the SSH/PUTTY private key file to connect with
    -ssh		        ssh method - the ssh command to use. Possible values are:
                        * "ssh" (default)
                        * "plink" (PUTTY)
    -exclude		    comma separated list of excluded vdisknames (lunonline check)
                        or consistency group names (luninsync check)
    -h -help   		    Print this help
    -v -verbose         verbose output (OK items are listed)

EOU
        exit (0);
}

# Set parameters for svc connection
$params->{'cluster_name'} = $cluster if $cluster;
$params->{'user'} = $user if $user;
$params->{'ssh_method'} = $ssh if $ssh;
$params->{'keyfile'} = $keyfile if $keyfile;

# Create the connection with the parameters set above.
my $svc = IBM::SVC->new($params);

if ($check eq "lunonline") {
        $svc_command = "lsvdisk";
        $item = "vdisks (luns)";
        $item_name = "name";
        $item_state = "status";
        &itemcheck(\%generic_states,\%excl)
    
} elsif ($check eq "luninsync") {
    # * consistent_synchronized
    # * consistent_copying
    # * inconsistent_stopped
    # * consistent_stopped
    # * idling
    # * consistent_disconnected'
    # * inconsistent_copying
    # * idling_disconnected
    # * inconsistent_disconnected
        $svc_command = "lsrcrelationship";
        $item = "consistency groups";
        $item_name = "consistency_group_name";
        $item_state = "state";
        &itemcheck(\%luninsync_states,\%excl)
    
} elsif ($check eq "lsarray") {
    # * offline - the array is offline on all nodes
    # * degraded - the array has deconfigured or offline members; the array is not fully redundant
    # * syncing - array members are all online, the array is syncing parity or mirrors to achieve redundancy
    # * initting - array members are all online, the array is initializing; the array is fully  redundant
    # * online - array members are all online, and the array is fully redundant
        $svc_command = "lsarray";
        $item = "mdisk";
        $item_name = "mdisk_name";
        $item_state = "status";
        &itemcheck(\%lsarray_states)
        
} elsif ($check eq "lsdrive") {
    # * online: blank
    # * degraded: populated if associated with an error
    # * offline: must be populated
    	$svc_command = "lsdrive";
        $item = "mdisk member";
        $item_name = "id";
        $item_state = "error_sequence_number";
        &itemcheck(\%lsdrive_states)

} elsif ($check eq "lsenclosure") {
    # Indicates if an enclosure is visible to the SAS network:
        $svc_command = "lsenclosure";
        $item = "enclosure(s)";
        $item_name = "id";
        $item_state = "status";
        &itemcheck(\%generic_states)
    
} elsif ($check eq "lsenclosurebattery") {
    # The status of the battery:
        $svc_command = "lsenclosurebattery";
        $item = "enclosurebatteries";
        $item_name = "battery_id";
        $item_state = "status";
        &itemcheck(\%generic_states)
    
} elsif ($check eq "lsenclosurecanister") {
    # The status of the canister:
        $svc_command = "lsenclosurecanister";
        $item = "enclosurecanister(s)";
        $item_name = "node_name";
        $item_state = "status";
        &itemcheck(\%generic_states)
    
} elsif ($check eq "lsenclosurepsu") {
    # The status of the psu(s)
        $svc_command = "lsenclosurepsu";
        $item = "enclosurepsu(s)";
        $item_name = "PSU_id";
        $item_state = "status";
        &itemcheck(\%generic_states)
    
} elsif ($check =~ m/^lsenclosureslot(\d+)$/ ) {
    # The status of enclosure slot port x. If the port is bypassed for multiple reasons, only one is shown.
    # In order of priority, they are:
    # * online: enclosure slot port x is online
    # * excluded_by_drive: the drive excluded the port
    # * excluded_by_enclosure: the enclosure excluded the port
    # * excluded_by_system: the clustered system (system) has excluded the port

        $svc_command = "lsenclosureslot";
        $item = "enclosureslots port" . $1;
        $item_name = "slot_id";
        $item_state = "port_" . $1 . "_status";
        &itemcheck(\%lsenclosureslot_states)
    
} else {
	$state = 'UNKNOWN';
	$message = "the check you provided does not exist";
}
# main check subroutine
sub itemcheck {
	# get hash reference(s) from subroutine call
	my $v7000_states=shift;
	my $excluded=shift;
    
	my @critical_items = "";
	my @warn_items = "";
	my @ok_items = "";
	my @all_items = "";
	my $criticalcount =  0;
    my $warncount =  0;
    my $okcount =  0;
    my ($items_desc, $item_desc, $final_item_state);

    # query storage cluster
    my ($rc,$all_items_ref) =  $svc->svcinfo($svc_command,{});

	if ($rc == 0) {
		@all_items = @$all_items_ref;
		if (scalar(@all_items) == 0) { 
			$state = 'WARNING';
			$message = "Could not find any entry for $item";
		} else {
			foreach my $items_params (@all_items) {
                $item_desc = "$items_params->{$item_name}";
                chomp($item_desc);
				#print Dumper($items_params);
				# ommit excluded and blank items
                next if $excluded->{$item_desc} || $item_desc =~ m/^s*$/g;
				$final_item_state = "$items_params->{$item_state}";
				if ($v7000_states->{$final_item_state} eq 'OK' ) {			
					$okcount++;
					push (@ok_items, $item_desc);
				} elsif ($v7000_states->{$final_item_state} eq 'WARNING' ) {
					$warncount++;
					$msg = "$item_desc ($final_item_state) ";
                    push (@warn_items, $msg);
				} elsif ($v7000_states->{$final_item_state} eq 'CRITICAL' ) {
					$criticalcount++;
					$msg = "$item_desc ($final_item_state) ";
					push (@critical_items, $msg);
					
				}

			}
		}
	} else {
     		print "Cannot connect to cluster $cluster\n";
        	exit $states{'CRITICAL'};
	}

	if ( $warncount == 0 && $criticalcount == 0 && $okcount > 0 ) {
		$state = 'OK';
		if ($verbose) {
			$message = "$state: all $item $final_item_state [" . join(" ",@ok_items) . " ]";
		} else {
			$message = "$state: all $item $final_item_state";
		}		
	} elsif ( $warncount > 0 && $criticalcount == 0  ) {
		$state = 'WARNING';
        $message = "$state:" .  join(" ",@warn_items) ;
	} elsif ( ( $warncount > 0 && $criticalcount > 0 ) || ( $warncount == 0 && $criticalcount > 0 )  ) {
                $state = 'CRITICAL';
                $message = "$state:" .  join(" ",@critical_items) . " " . join(" ",@warn_items) ;
        } else {
		$state = 'UNKNOWN';
		$message = "$state: Could not find status information or items" ;
	}
}

print $message."\n";
exit $states{$state};