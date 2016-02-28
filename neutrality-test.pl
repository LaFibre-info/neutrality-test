#!/usr/bin/perl

# neutrality test
# based on test-neutralite.bat by Vivien GUEANT @ https://lafibre.info
# written by Kirth Gersen under GNU GPLv3 http://www.gnu.org/licenses/gpl-3.0.en.html
# kgersen at hotmail dot com
# project home : https://github.com/kgersen/neutrality-test

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage; #TODO bug ?

my %sizes = (
  "1M"  => 1,
  "2M"  => 2,
  "5M" => 5,
  "10M" => 10,
  "20M"  => 20,
  "50M"  => 50,
  "100M"  => 100,
  "200M"  => 200,
  "500M"  => 500,
  "1G" => 1000,
  "5G"  => 5000
  );

# parameters & constants
my $debug = 0;
my $ul_only = 0;
my $dl_only = 0;
my $server = '3.testdebit.info';
my $test = '';
my $sizename = '10M';
my $temppath = 'temp';
# cmd line options
GetOptions(
  'server=s'=> \$server,
  'test=s'=> \$test,
  'size=s'=> \$sizename,
  'tmppath=s' => $temppath,
  'ul' => \$ul_only,
  'dl' => \$dl_only,
  'debug' => \$debug,
  'help|?' => sub { pod2usage(1) }) or pod2usage(2);

# when in doubt
print "$0 is running on $^O  \n" if $debug;

# null device is OS specific
my $null = ($^O eq 'Win32') ? 'NUL' : '/dev/null';
print "null device is $null\n" if $debug;

# globals
my @G_tempdled = (); # store downloaded files to clean up at the end
# TODO get upload & download sizes
my $size = $sizes{$sizename};

# do all tests
if ($test eq '') {
 while (my $line = <DATA>) {
    print("parsing line: $line\n") if $debug;
    last if ($line =~ "end");
    chomp $line;
    doTest($line,$size,$temppath);
  }
}
# do only a specific test
else
{
  doTest($test,$size,$temppath);
}

# clean up
foreach my $file ( @G_tempdled ) {
  print "removing file $file\n";
  unlink $file or warn "Could not unlink $file: $!";
}


exit;

# performs a test
# TODO
sub doTest {
  print "doTest: $_[0]\n" if $debug;
  my $size = $_[1];
  my $temp = $_[2];
  my ($ip, $port, $proto, $type, $direction) = split /\s+/, $_[0];
  print  "D=$direction, IP=$ip, PORT=$port, PROTO=$proto, TYPE=$type, SIZE=$size, TMP=$temp\n" if $debug;

  my $url = "";
  # get the temp file if needed
  if (($direction eq "POST") && !$dl_only)
  {
    my $tempfile = $temp . $$ . '-' . $size . $type;
    $tempfile = lc $tempfile;
    print "tempfile : $tempfile\n" if $debug;

    if (!grep { $tempfile eq $_ } @G_tempdled)
    {
      my $curlcmd = "curl -s -o $tempfile $proto://$server:$port/fichiers/${size}Mo/${size}Mo$type";
      print "$curlcmd \n" if $debug;
      my $rc = `$curlcmd`;
      if ($? != 0) {
        print "!!! curl error for $curlcmd !!!\n";
      }
      else {
        push @G_tempdled, $tempfile;
      }
    }
    $url = '-F "filecontent=@' .  $tempfile . '"';
    $url .= " $proto://$server:$port";
  }
  elsif (!$ul_only)
  {
    # http://3.testdebit.info/fichiers/%tailleDL%Mo/%tailleDL%Mo.zip
    # TODO this is so specific to that server...
    $url = "$proto://$server:$port/fichiers/${size}Mo/${size}Mo$type";
  }
  # did we build an url ?
  return("skiped") if ($url eq "");

  # TODO: this is curl specific  , put it in doCurl ?
  if (lc $proto eq "https")
  {
    $url = "--insecure $url";
  }

  #perform the Curl
  print "$ip $direction $url" if $debug;

  my $result = doCurl($ip,$direction,$url);
  print "IPv$ip+TCP$port  +$proto $type: $result\n";
}


# do http download and compute metrics
# args:
#    4 or 6
#    POST or GET
#    rest of the curl args
# TODO: split in 2, seperate curl'ing & calculations from pretty pretting
sub doCurl {
  my ($ip, $dir, $url) = @_;
  print("doCurl args = @_\n") if $debug;
  my $sizeparam = ($dir eq 'GET') ? "size_download" : "size_upload";
  my $curlcmd = "curl -$ip -s --write-out \"%{time_namelookup} %{time_connect} %{time_starttransfer} %{time_total} %{$sizeparam}\" -o $null $url"; #  2>&1 ?
  print "$curlcmd \n" if $debug;
  my $result = `$curlcmd`;

  if ($? != 0) {
    print "!!! curl error for @_ !!!\n";
  }
  else {
    # hacky: french locale decimal separator
    $result =~ tr/,/./;
    print "result : $result \n" if $debug;
    my ($time_namelookup, $time_connect, $time_starttransfer, $time_total, $size_transfered) = split / /, $result;
    if ($debug) {
      print "time_namelookup : $time_namelookup\n";
      print "time_connect : $time_connect\n";
      print "time_starttransfer : $time_starttransfer\n";
      print "time_total : $time_total\n";
      print "$sizeparam : $size_transfered bytes\n";
    }
    $time_namelookup = $time_namelookup*1000;

    $time_connect *= 1000;
    my $Ping = $time_connect-$time_namelookup;

    $time_starttransfer = $time_starttransfer*1000-$time_connect;

    $time_total *= 1000;
    my $temps_transfert = $time_total-$time_starttransfer;

    my $bw = sprintf("%.2f",  $size_transfered*8/1000/$temps_transfert);

    my $dirLabel= ($dir =~ "POST") ?"Up" : "Down";

    return "$bw Mb/s (DNS:${time_namelookup}ms SYN:${Ping}ms $dir:${time_starttransfer}ms $dirLabel:${temps_transfert}ms)";
  }
}

__DATA__
4 80   http  .zip GET
4 80   http  .jpg GET
4 80   http  .mp4 GET
4 80   http  .pdf GET
4 443  https .zip GET
4 443  https .jpg GET
4 554  http  .zip GET
4 554  http  .jpg GET
4 554  http  .mp4 GET
4 993  https .zip GET
4 993  https .jpg GET
4 1194 https .zip GET
4 1194 https .jpg GET
4 6881 http  .zip GET
4 6881 http  .jpg GET
4 8080 http  .zip GET
4 8080 http  .jpg GET
4 8080 http  .mp4 GET
6 80   http  .zip GET
6 80   http  .jpg GET
6 80   http  .mp4 GET
6 443  https .zip GET
6 554  http  .zip GET
6 1194 https .zip GET
6 6881 http  .zip GET
6 8080 http  .zip GET
4 80   http  .zip POST
4 80   http  .jpg POST
4 80   http  .mp4 POST
4 443  https .zip POST
4 554  http  .zip POST
4 1194 https .zip POST
4 6881 http  .zip POST
4 8080 http  .zip POST
6 80   http  .zip POST
6 80   http  .jpg POST
6 80   http  .zip POST
6 443  https .zip POST
6 554  http  .zip POST
6 1194 https .zip POST
6 6881 http  .zip POST
6 8080 http  .zip POST
end

=TODO
=pod
=head1 neutrality-test
test your ISP neutrality
=head1 SYNOPSIS
neutrality-test [options]
 Options:
   -debug           display debug informations
   -help            brief help message
=head1 OPTIONS
=over 8
=item B<-help>
Print a brief help message and exits.
=item B<-debug>
Prints display debug informations.
=back
=head1 DESCRIPTION
B<This program> TODO.
=cut
