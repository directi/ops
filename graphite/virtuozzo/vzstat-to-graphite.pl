#!/usr/bin/perl -w
# expects output columns as below - ignore all other lines
# $ sudo /usr/sbin/vzstat -b -m -c B -t -o id,vm,sw,km,proc,cpu,sock,ior,iow,rx,tx,rxp,txp
#
#   CTID   %VM         %SW   %KM        PROC     CPU     SOCK      IOR      IOW       RX       TX    RXP    TXP 
#   2434 1.6/2.1  3.9/ 4.0GB 0.1/MAX 1/200/32567 5.13/3.1 276/MAX        0   221551    26931   360989  240/s  307/s
#   2368 0.5/1.4  4.1/ 4.0GB 0.1/MAX 1/132/32567 2.52/2.4 212/MAX    54108   167736     3256    22363   22/s   34/s

#use Data::Dumper;

use strict;
use IO::Socket::INET;

#change this to suit your infra 
my $prefix = "graphite.virtuozzo"; 
my $carbon_server = "carbon.host.com";
my $carbon_port = "2003";

# metric path - change this to suit you infra
my $hostname = `hostname`;
my $hn = chomp $hostname;
my @hname = split( '\.', $hostname);
my @rhname = reverse @hname;
my $revhname = join( '.', @rhname);
my $mprefix = $prefix . "." .  $revhname . "." . "per-vps";

# code follows
my $str;
my $sock = IO::Socket::INET->new(
		PeerAddr => $carbon_server,
		PeerPort => $carbon_port,
		Proto => 'tcp'
		);

sub send_metrics {
	$sock->send($_[0]);	
}

sub calc_used_percent {
  my ($used , $alloted ) = split( '\/' , $_[0]);
  my $used_percent = ($used / $alloted ) * 100;
  return $used_percent
}

open DATA, "/usr/sbin/vzstat -b -m -c B -t -o id,vm,sw,km,proc,cpu,sock,ior,iow,rx,tx,rxp,txp|"   or die "Couldn't execute program: $!";
while ( defined( my $line = <DATA> )  ) {
	chomp($line);
  next if ( $line !~ m/^\s+([0-9]+)/ );

  #sanitizing the vzstat output for easier parsing
  # remove space after / in %sw stats
  $line =~ s/\/ /\//g;
  #remove whitespaces/tabs at the start of the line 
  $line =~ s/^[ \t]+//g;
  # remove GB form the swap stats
  $line =~ s/GB//g;

  #split to a array on spaces or tabs
  my @values = split (/[ \t]+/,$line);
  my $ctid = $values[0];
  next if ( $ctid == 1);

  my $metric_prefix = $mprefix . "." . $values[0];
  $str = calc_used_percent($values[1]);
  send_metrics($metric_prefix . "." . "vm_used_percent " . $str . " " . time() . "\n");

  my ($swp) = split ( '\/', $values[2]);
  send_metrics($metric_prefix . "." . "sw_used_percent " . $swp . " " . time() . "\n");

  my ($km) = split ( '\/', $values[3]);
  send_metrics($metric_prefix . "." . "km_used_percent " . $km . " " . time() . "\n");

  my ($proc_r, $proc_t) = split ( '\/', $values[4]);
  send_metrics($metric_prefix . "." . "proc_running " . $proc_r . " " . time() . "\n");
  send_metrics($metric_prefix . "." . "proc_total " . $proc_t . " " . time() . "\n");

  $str = calc_used_percent($values[5]);
  send_metrics($metric_prefix . "." . "cpu_used_percent " . $str . " " . time() . "\n");

  my ($sock) = split ( '\/', $values[6]);
  send_metrics($metric_prefix . "." . "sockets " . $sock . " " . time() . "\n");

  send_metrics($metric_prefix . "." . "io_read " . $values[7] . " " . time() . "\n");
  send_metrics($metric_prefix . "." . "io_write " . $values[8] . " " . time() . "\n");
  
  send_metrics($metric_prefix . "." . "net_rcvd_bytes " . $values[9] . " " . time() . "\n");
  send_metrics($metric_prefix . "." . "net_sent_bytes " . $values[10] . " " . time() . "\n");

  my ($rxp) = split ( '\/', $values[11]);
  my ($txp) = split ( '\/', $values[12]);
  send_metrics($metric_prefix . "." . "net_rcvd_pps " . $rxp . " " . time() . "\n");
  send_metrics($metric_prefix . "." . "net_sent_pps " . $txp . " " . time() . "\n");
  #print Dumper(@values);
	
}
close DATA;
$sock->shutdown(2);
