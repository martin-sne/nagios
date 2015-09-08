#!/usr/bin/perl 

####### Author $id ml (C) IPB 2011


####### TODO:
####### Gauge for BGP in/out prefixes
####### MIB1:     BGP4-V2-MIB-JUNIPER
####### OID:     .1.3.6.1.4.1.2636.5.1.1

###### SNMPv3 Login


####### Counter for in/out update messages
####### MIB2:     BGP4-MIB
####### OID:     .1.3.6.1.2.1.15

use Net::SNMP;
use Getopt::Long;
&Getopt::Long::config('bundling');

GetOptions(
        "h|help"           => \$opt_h,
        "H=s"              => \$host,    
        "R=s"              => \$remote_peer,
        "C=s"              => \$community,
        );


if ($opt_h) {
        print_usage();
}

if ( !$host || !$remote_peer || !$community) {
        print_usage();
}

sub print_usage {
        print <<EOU;

    Author: Martin Leucht IPB GmbH      

    Usage: ./check_bgp_neighbor.pl -H [Hostname/IP]  -C [SNMP Community] -R [remote_peer address]  [-h]


    Options:

    -H          Hostname/IP 
    -R          IP address of bgp remote neighbor
    -C          SNMP v1/v2c Community String
    -h --help   Print this help

EOU
        exit (0);
}


$tmpfile="/tmp/bgp_counter_${host}_${remote_peer}";

%STATES=('1'=>idle,'2'=>'connect','3'=>'active','4'=>'opensent','5'=>'openconfirm', '6'=>'established');
%ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);

%oids = (
	      'BgpM2PeerState'				=>	'.1.3.6.1.2.1.15.3.1.2.',
	      'bgpPeerRemoteAS'				=>	'.1.3.6.1.2.1.15.3.1.9.',
	      'counter_BgpM2PeerInUpdates'                    =>      '.1.3.6.1.2.1.15.3.1.10.',
        'counter_BgpM2PeerOutUpdates'                  =>      '.1.3.6.1.2.1.15.3.1.11.',
        'counter_BgpM2PeerInTotalMessages'             =>      '.1.3.6.1.2.1.15.3.1.12.',
        'counter_BgpM2PeerOutTotalMessages'            =>      '.1.3.6.1.2.1.15.3.1.13.',
        'counter_BgpM2PeerFsmEstablishedTrans'         =>      '.1.3.6.1.2.1.15.3.1.15.',	
);	

($session, $error) = Net::SNMP->session(
   	 -hostname  => $host,
       	 -community => $community,
         -port      => 161,
         -timeout   =>   5
    );

if (!defined($session)) {
   printf("ERROR opening session: %s.\n", $error);
   exit $ERRORS{"CRITICAL"};
}


%data = ();

foreach $key (keys %oids) {
	$real_oid =  $oids{$key}.${remote_peer};
	$result = $session->get_request(
        	-varbindlist => [ $real_oid ],
	);
  

	if (!defined $result) {
     		 printf "BGP Peer not found : ERROR: %s.\n", $session->error();
      		$session->close();
		
      		exit $ERRORS{"CRITICAL"};
   		}
 
        # fill new hash with data	

	#print "--- $result->{$real_oid} ---\n";
	
	$data{$key}  = $result->{$real_oid};

}

$session->close();


$in_updates = $data{'counter_BgpM2PeerInUpdates'};
$out_updates = $data{'counter_BgpM2PeerOutUpdates'};
$in_messages = $data{'counter_BgpM2PeerInTotalMessages'};
$out_messages = $data{'counter_BgpM2PeerOutTotalMessages'};
$fsm_estab_trans = $data{'counter_BgpM2PeerFsmEstablishedTrans'};
$bgp_state = $data{'BgpM2PeerState'};
$remote_as = $data{'bgpPeerRemoteAS'};


$update_time = time;


if (! -e $tmpfile) {

        open(WRITE,"+>>$tmpfile") || die "Can not open file $tmpfile\n";

                printf WRITE ( "%s:%d:%d:%.0ld:%.0ld:%.0ld\n", $update_time,$in_updates,$out_updates,$in_messages,$out_messages,$fsm_estab_trans );
                print "Unknown, not enough data available\n";
                exit $ERRORS{"UNKNOWN"};
        close(WRITE);
        }

else { open(READ,"<$tmpfile") || die "Can not open file $tmpfile\n";
        while (<READ>) {
                push(@lines,$_);
                }
        close(READ);
        }


($lasttime, $last_in_updates, $last_out_updates, $last_in_messages, $last_out_messages, $last_fsm_estab_trans) = split(/:/,$lines[$#lines]);


if ( $in_updates < $last_in_updates || $out_updates < $last_out_updates || $in_messages < $last_in_messages || $out_messages < $last_out_messages ||  $fsm_estab_trans < $last_fsm_estab_trans ) {
	 	print "Unknown, last value smaller then current, discarding data\n";

		`mv $tmpfile /usr/local/nagios/var/tmp/bgp/crashed/bgp_counter_${host}_${peer}`;
        	exit $ERRORS{"UNKNOWN"};
		}


elsif ($bgp_state == 6 ) { 

        open(APPEND, "+>>$tmpfile") || die "Can not open file $tmpfile\n";
        printf APPEND ( "%s:%d:%d:%d:%d:%d\n", $update_time, $in_updates, $out_updates, $in_messages, $out_messages, $fsm_estab_trans );
        close(APPEND);
        print "OK: BGP in state $STATES{$bgp_state} (PEER: ${remote_peer} , AS: ${remote_as}) | in_updates=${in_updates}c out_updates=${out_updates}c in_messages=${in_messages}c out_messages=${out_messages}c fsm_estab_trans=${fsm_estab_trans}c";
        exit $ERRORS{"OK"};
        }

else {  print "CRITICAL: BGP Session in state $STATES{$bgp_state} (PEER: ${remote_peer} , AS: ${remote_as})";
	exit $ERRORS{"CRITICAL"};
	}



	

