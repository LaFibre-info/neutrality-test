#!/usr/bin/perl

# neutrality test - draft version . no version number yet TODO
# based on test-neutralite.bat by Vivien GUEANT @ https://lafibre.info
# written by Kirth Gersen under GNU GPLv3 http://www.gnu.org/licenses/gpl-3.0.en.html
# kgersen at hotmail dot com
# project home : https://github.com/kgersen/neutrality-test

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage; #TODO bug ?

# parameters & constants
my $debug = 0;
my $ul_only = 0;
my $dl_only = 0;
my $server = '3.testdebit.info';
my $test = '';
my $temppath = 'temp';
my $size_upload = '10M';
my $size_download = '10M';
my $timeout = 0;
# cmd line options
GetOptions(
  'server=s'=> \$server,
  'test=s'=> \$test,
  'size=s'=> \&ParseSize,
  'tmppath=s' => \$temppath,
  'timeout=i' => \$timeout,
  'ul' => \$ul_only,
  'dl' => \$dl_only,
  'debug' => \$debug,
  'help|?' => sub { pod2usage(1) }) or pod2usage(2);

# parse -size <value>
sub ParseSize {
      my ($n, $v) = @_;
      print("parsing option $n with value $v\n") if $debug;
      my $size_value = qr/[1-9][0-9]*[KMGT]?/;
      if ($v =~ /^($size_value)$/)
      {
        $size_download = $1;
        $size_upload = $1;
        print "Found a single size $1\n" if $debug;
      }
      elsif ($v =~ /^($size_value)\/($size_value)$/) {
        $size_download = $1;
        $size_upload = $2;
        print "Found a dual size $1 and $2\n" if $debug;

      }
      else {die('bad size value');}
}

# when in doubt
print "$0 is running on $^O  \n" if $debug;

# catch signals
$SIG{INT} = sub { print "Caught a sigint $!\n"; cleanup(); die; };
$SIG{TERM} = sub { print "Caught a sigterm $!\n"; cleanup(); die; };

# null device is OS specific
my $null = ($^O eq 'Win32') ? 'NUL' : '/dev/null';
print "null device is $null\n" if $debug;

# globals
my @G_tempdled = (); # store downloaded files to clean up at the end
# TODO get upload & download sizes

# do all tests
if ($test eq '') {
 while (my $line = <DATA>) {
    print("parsing line: $line\n") if $debug;
    last if ($line =~ "end");
    chomp $line;
    my ($ip, $port, $proto, $type, $direction) = parseTest($line);
    my $size = ($direction eq 'GET') ? $size_download : $size_upload;
    my $r = doTest($ip, $port, $proto, $type, $direction, $size, $timeout);
    print "doTest returned $r" if $debug;
  }
}
# do only a specific test
else
{
  my ($ip, $port, $proto, $type, $direction) = parseTest($test);
  my $size = ($direction eq 'GET') ? $size_download : $size_upload;
  my $r = doTest($ip, $port, $proto, $type, $direction, $size , $timeout);
  print "doTest returned $r" if $debug;
}

# clean up
cleanup();

exit;

# -------------------------------------------------------------------------

sub cleanup {
  foreach my $file ( @G_tempdled ) {
    print "removing file $file\n" if $debug;
    unlink $file or warn "Could not unlink $file: $!";
  }
}

# parse test. TODO some asserts ?
sub parseTest {
  my ($ip, $port, $proto, $type, $direction) = split /\s+/, $_[0];
  print  "parsed D=$direction, IP=$ip, PORT=$port, PROTO=$proto, TYPE=$type\n" if $debug;
  return ($ip, $port, $proto, $type, $direction);
}

# performs a test
# TODO
sub doTest {
  my ($ip, $port, $proto, $type, $direction, $size, $timeout) = @_;
  my $url = "";
  # get the temp file if needed
  if (($direction eq "POST") && !$dl_only)
  {
    my $tempfile = $temppath . $$ . '-' . $size . $type;
    $tempfile = lc $tempfile;
    print "tempfile : $tempfile\n" if $debug;

    if (!grep { $tempfile eq $_ } @G_tempdled)
    {
      push @G_tempdled, $tempfile;
      my $curlcmd = "curl -s -o $tempfile $proto://$server:$port/fichiers/${size}o/${size}o$type";
      print "$curlcmd \n" if $debug;
      print "downloading temporary file $tempfile...";
      my $rc = `$curlcmd`;
      if ($? != 0) {
        print "!!! curl error for $curlcmd !!!\n";
        #TODO: stop or continue ?
        print"error!\n";
        return "error";
      }
      print "done.\n";
    }
    $url = '-F "filecontent=@' .  $tempfile . '"';
    $url .= " $proto://$server:$port";
  }
  elsif (!$ul_only)
  {
    # http://3.testdebit.info/fichiers/%tailleDL%Mo/%tailleDL%Mo.zip
    # TODO this is so specific to that server...
    $url = "$proto://$server:$port/fichiers/${size}o/${size}o$type";
  }
  # did we build an url ?
  return("skiped") if ($url eq "");

  # TODO: this is curl specific  , put it in doCurl ?
  if (lc $proto eq "https")
  {
    $url = "--insecure $url";
  }

  #perform the Curl
  print "$ip $direction $url\n" if $debug;

  printf "IPv$ip+TCP%-6s+%6s %5s: ",$port,$proto,$type;
  my $result = doCurl($ip,$direction,$timeout,$url);
  print "$result\n";
  return "ok";
}


# do http download and compute metrics
# args:
#    4 or 6
#    POST or GET
#    timeout
#    rest of the curl args
# TODO: split in 2, seperate curl'ing & calculations from pretty pretting
sub doCurl {
  my ($ip, $dir, $timeout, $url) = @_;
  print("doCurl args = @_\n") if $debug;
  my $sizeparam = ($dir eq 'GET') ? "size_download" : "size_upload";
  my $timeout_cmd = ($timeout == 0) ? "" : "--max-time $timeout";
  my $curlcmd = "curl -$ip -s $timeout_cmd --write-out \"%{time_namelookup} %{time_connect} %{time_starttransfer} %{time_total} %{$sizeparam} %{http_code}\" -o $null $url"; #  2>&1 ?
  print "$curlcmd \n" if $debug;
  my $result = `$curlcmd`;
  my $curlRC = $? >>8;
  print "curl return code = $curlRC\n" if $debug;
  if ($curlRC != 0 && $curlRC != 28) {
    print "!!! curl error for @_ !!! RC = $curlRC\n";
  }
  else {
    # hacky: french locale decimal separator
    $result =~ tr/,/./;
    print "result : $result \n" if $debug;
    my ($time_namelookup, $time_connect, $time_starttransfer, $time_total, $size_transfered, $httpcode) = split / /, $result;
    if ($debug) {
      print "time_namelookup : $time_namelookup\n";
      print "time_connect : $time_connect\n";
      print "time_starttransfer : $time_starttransfer\n";
      print "time_total : $time_total\n";
      print "$sizeparam : $size_transfered bytes\n";
      print "http_code : $httpcode\n";
    }
    # TODO if 200 & 100 not too restrictive ?
    return "error (http $httpcode)" unless $httpcode eq "200" || $httpcode eq "100";
    $time_namelookup = $time_namelookup*1000;

    $time_connect *= 1000;
    my $Ping = $time_connect-$time_namelookup;

    $time_starttransfer = $time_starttransfer*1000-$time_connect;

    $time_total *= 1000;
    my $temps_transfert = $time_total-$time_starttransfer;

    my $bw = sprintf("%.2f",  $size_transfered*8/1000/$temps_transfert);

    my $dirLabel= ($dir =~ "POST") ?"Up" : "Down";
    my $timedout = ($curlRC == 28) ? "timeout":'full';
    $bw = sprintf("%8s",$bw);
    return "$bw Mb/s (DNS:${time_namelookup}ms SYN:${Ping}ms $dir:${time_starttransfer}ms $dirLabel:${temps_transfert}ms:$timedout)";
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
