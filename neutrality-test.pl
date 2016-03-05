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
use IPC::Open3;
use POSIX "strftime";
use POSIX ":sys_wait_h";
use IO::Handle;
use Config;
use LWP::Simple;
use IO::String;
use URI::URL;

our $VERSION = 1.1.3;

=pod

=head1 NAME
  My::Module

=head1 SYNOPSIS
neutrality-test [options] [url]

Arguments:

  if no url argument, stdin is used instead.
  The url (or stdin) must contain a list of test, one per line.
  See below for the syntax.

Options:
   -debug           display debug informations
   -help            brief help message
   -4               IPv4 only
   -6               IPv6 only
   -ul              perform only upload tests
   -dl              perform only download tests
   -time <value>    timeout, in seconds, for each test. default is 0 = no timeout
   -csv             output results as a 'database ready' table

Syntax of test line:

   GET  4|6 <url> <...>         performs a download test from <url> in IPv4 ou IPv6
   PUT  4|6 <size> <url> <...>  performs an upload test of <size> bytes to <url> in IPv4 ou IPv6
   PRINT <rest of line>         print the rest of the line to stdout
   TIME <value>                 change the timeout of following tests to <value> seconds. 0 = no timeout
   # <rest of line>             comment, ignore rest of the line

<url>: a valid url. Accepted schemes are : http, https, ftp
<...>: additional arguments passed directly to the curl command (for instance --insecure)
<size> format : <value>
  <value> = <number> or <number>[KMGT]
  K, M, G,T denote: Kilo, Mega, Giga and Tera (each are x1000 increment not 1024)


=cut

# parameters & constants
my $debug = 0;
my $ul_only = 0;
my $dl_only = 0;
my $timeout = 0;
my $csv = 0;
my $ip4only = 0;
my $ip6only = 0;
my $testsurl = "-";

# cmd line parsing - options
GetOptions(
  'timeout=i' => \$timeout,
  'csv' => \$csv,
  'ul' => \$ul_only,
  'dl' => \$dl_only,
  '-4' => \$ip4only,
  '-6' => \$ip6only,
  'debug' => \$debug,
  'help' => sub { pod2usage(-verbose => 1) }) or pod2usage( {-verbose => 2 });

# get the only argument which is the test url or none if stdin
pod2usage( {-verbose => 2 }) if (@ARGV > 1);
if (@ARGV == 1) { $testsurl = $ARGV[0]; }
print "tests url = $testsurl\n" if $debug;

# end of cmd line parsing

# when in doubt
print "$0 is running on $^O  \n" if $debug;

# catch signals
$SIG{INT} = sub { print "Caught a sigint $!\n"; cleanup(); die; };
$SIG{TERM} = sub { print "Caught a sigterm $!\n"; cleanup(); die; };
$SIG{PIPE} = sub { print "Caught a sigpipe $!\n" if $debug; }; # dont remove this or PUT tests will fail if timeout

# null device is OS specific
my $null = ($^O eq 'MSWin32') ? 'NUL' : '/dev/null';
print "null device is $null\n" if $debug;

# input file is stdin or content of $testsurl
my $handle;
if ($testsurl eq "-")
{
  $handle= *STDIN;
}
else
{
   # hacky because we want to loop on a file handle
   my $content = get($testsurl);
   die "error getting $testsurl" unless defined $content;
   $handle = IO::String->new($content);
}

# HEADER
printout ("Running on $Config{osname} - $Config{osvers} - $Config{archname}\n");
my $datetime = localtime();
printout ("Started at: $datetime\n");
# 2016-03-04 20:33:GET;4;http;80;919.41;4;3;4;995;timeout;114351224;200;999;http://3.testdebit.info/fichiers/5000Mo/5000Mo.zip
print ("DATE;CMD;IP;PROTO7;PORT;BW;DNS;PING;START;DURATION;TIMEDOUT;SIZE;CODE;TIME;URL\n") if ($csv);

# loop thru tests & perform them
my $linenum = 0;
while (defined (my $line = <$handle>)) {
  chomp $line;
  $line =~ s/^\s+|\s+$//g; # = trim
  $linenum++;
  print("parsing line: $line\n") if $debug;
  next if ($line eq ''); # skip blank lines

  # syntax of a line
  # GET <ip> <url>	<...> performs a download test
  # PUT <ip> <size> <url> <...> peforms an upload test
  # TIME <value> change timeout value
  # PRINT <...>	print out the rest of the line
  # #<...>	comment - ignore the lien
  my $cmdpat = qr/GET|PUT|PRINT|TIME|#/i;
  if ($line =~ /^($cmdpat)\s*(.*)$/)
  {
    my $command = $1;
    my $args = $2;
    print "command: $command --> args: $args\n" if $debug;
    if ($command eq "PRINT")
    {
      print "$args\n" if (!$csv);
    }
    elsif ($command eq "#")
    {
      print "skipped comment at line $linenum\n" if $debug;
    }
    elsif ($command eq "TIME")
    {
      print "parse $args for new time\n" if $debug;
      if ($args =~ m/\s*([1-9][0-9]*)/)
      {
        $timeout = $1;
        print "changing timeout to $timeout\n" if $debug;
      }
      else
      {
        print "error bad time value line $linenum: $args\n";
        last;
      }

    }
    elsif ($command eq "GET")
    {
      # GET 4|6 URL ...
      if ($args =~ m/^\s*([4|6])\s+(\S+)(.*)$/)
      {
        my $ip = $1;
        my $url = url $2;
        my $extra = $3;
        if (grep { $url->scheme eq $_ } qw(http https ftp)) #TODO add more ?
        {
          my $port = $url->port;
          print ("GET $ip proto: ", $url->scheme, " port: $port\n") if $debug;
          my $r = doTest("GET", $ip, $url, 0, $timeout, $extra);
          print "doTest returned $r" if $debug;
        }
        else
        {
          print "error line $linenum: GET ip=$ip, url=$url (unknown proto) extra=$extra\n";
          last;
        }
      }
      else
      {
        print "bad GET command line $linenum: $line\n";
        last:
      }

    }
    elsif ($command eq "PUT")
    {
      # GET 4|6 SIZE URL ...
      if ($args =~ m/^\s*([4|6])\s+([1-9][0-9]*[KMGT]?)\s+(\S+)(.*)$/)
      {
         my $ip = $1;
         my $size = $2;
         my $url = url $3;
         my $extra = $4;
         if (grep { $url->scheme eq $_ } qw(http https ftp))
         {
           my $port = $url->port;
           print ("PUT $ip size $size proto: ", $url->scheme, " port: $port\n") if $debug;
           my $r = doTest("PUT", $ip, $url, $size, $timeout, $extra);
           print "doTest returned $r" if $debug;
         }
         else
         {
           print "error line $linenum: PUT ip=$ip, url=$url (unknown proto) extra=$extra\n";
           last;
         }
      }
      else
      {
        print "bad PUT command line $linenum: $line\n";
        last;
      }
    }
    else
    {
      print "syntax error line $linenum: unknown command $command\n";
      last;
    }
  }
  else
  {
    print "syntax error line $linenum: $line\n";
    last;
  }
}

# FOOTER
$datetime = localtime();
printout ("Ended at: $datetime\n");

# clean up
cleanup();

exit;

# -------------------------------------------------------------------------

sub cleanup {
  # nothing more
}

# performs a test
# it's the big one!
sub doTest {
  my ($direction, $ip, $url, $size, $timeout, $extra) = @_;
  return("skiped ip6") if ($ip4only && $ip eq 6);
  return("skiped ip4") if ($ip6only && $ip eq 4);

  my $curl = $url->as_string . " $extra";

  if ($direction eq "PUT")
  {
    return "skiped" if $dl_only;
    $curl = '-T "-" ' . $curl;
  }
  elsif ($direction eq "GET")
  {
    return "skiped" if $ul_only;
  }
  else
  {
     die "fatal error - unexcepted value of direction = $direction";
  }

  #perform the Curl
  print "$ip $direction $url\n" if $debug;

  if (!$csv) {
    printf ("IPv$ip %-6s %-6s : ",$url->scheme,$url->port);
  }

  # setup the curl command
  my $sizeparam = ($direction eq 'GET') ? "size_download" : "size_upload";
  my $timeout_cmd = ($timeout == 0) ? "" : "--max-time $timeout";
  my $curlcmd = "curl -$ip -s $timeout_cmd --write-out \"%{time_namelookup} %{time_connect} %{time_starttransfer} %{time_total} %{$sizeparam} %{http_code}\" -o $null $curl";
  print "CURL= $curlcmd \n" if $debug;
  my $result = '';
  my $curlRC = -1;

  # perform the curl
  if ($direction eq "GET") {
    $result = `$curlcmd`;
    $curlRC = $? >>8;
  }
  else #assume PUT
  {
    my($wtr, $rdr, $err);
    my $childpid = open3($wtr, $rdr, $err, "$curlcmd");
    $wtr->autoflush(1);
    binmode $wtr;
    my $sent = 0;
    my $totaltosend = Sizetobytes($size);
    print ("size is $size, so total bytes to send is $totaltosend\n") if $debug ;

    my @chunk;
    my $chuck_size = 4096;
    for (my $idx = 0; $idx < $chuck_size; $idx++) {
        $chunk[$idx] = $idx % 256;
    }
    my $pack = pack('C*',@chunk);

    my $childisalive = 1;
    while (1)
    {
      if (waitpid ($childpid,WNOHANG)) {
        print "child ended\n" if $debug;
        $curlRC = $? >> 8;
        $childisalive = 0;
        last;
      }

      print $wtr $pack;
      $sent += $chuck_size ;
      last if ($sent >= $totaltosend);
    }
    close ($wtr);
    $result = <$rdr>;
    if ($childisalive)
    {
      waitpid ($childpid,0);
      $curlRC = $? >> 8;
    }
  }

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

    # TODO check for more?
    if (!grep { $httpcode eq $_ } qw(000 100 150 200 405))
    {
      print  "error unhandled scheme code: $httpcode\n";
      return "error (http $httpcode)";
    }

    $time_namelookup = $time_namelookup*1000;

    $time_connect *= 1000;
    my $Ping = $time_connect-$time_namelookup;

    $time_starttransfer = $time_starttransfer*1000-$time_connect;

    $time_total *= 1000;
    my $transfer_time = $time_total-$time_starttransfer;

    my $bw = sprintf("%.2f",  $size_transfered*8/1000/$transfer_time);

    my $dirLabel= ($direction =~ "PUT") ?"Up" : "Down";
    my $timedout = ($curlRC == 28) ? "timeout":'full';

    if ($csv) {
      print strftime("%Y-%m-%d %H:%M:%S;", localtime(time)),
        "$direction;$ip;" , $url->scheme , ";" , $url->port , ";",
        "$bw;${time_namelookup};${Ping};${time_starttransfer};${transfer_time};$timedout;$size_transfered;$httpcode;$time_total;",
        $url->as_string , "\n";
    }
    else  {
      # TODO
      if ($httpcode eq "000") { print "!timeout before receving any data!\n" ; return;}
      $bw = sprintf("%8s",$bw);
      $time_namelookup = sprintf("%.0f",$time_namelookup);
      $Ping = sprintf("%.0f",$Ping);
      $time_starttransfer = sprintf("%.0f",$time_starttransfer);
      $transfer_time = sprintf("%.0f",$transfer_time);
      $size_transfered = scaleIt($size_transfered);
      print "$bw Mb/s (DNS:${time_namelookup}ms SYN:${Ping}ms $direction:${time_starttransfer}ms $dirLabel:${transfer_time}ms:$timedout:$size_transfered)\n";
    }
  }
}

sub printout {
  return if ($csv);
  print @_;
}

sub Sizetobytes {
  my $size = $_[0];
  print "converting $size\n" if $debug;
  my $value = qr/[1-9][0-9]*/;
  my $unit = qr/[KMGT]$/;
  if ($size =~ /^($value)($unit)$/)
  {
    if    ($2 eq "K") { $size = $1 * 1000; }
    elsif ($2 eq "M") { $size = $1 * 1000*1000; }
    elsif ($2 eq "G") { $size = $1 * 1000*1000*1000; }
    elsif ($2 eq "T") { $size = $1 * 1000*1000*1000*1000; }
		else
      { die "fatal error in Sizetobytes\n"; }
  }

  return $size;
}

# http://www.perlmonks.org/?node_id=378542
sub scaleIt {
    my( $size, $n ) =( shift, 0 );
    ++$n and $size /= 1000 until $size < 1000;
    return sprintf "%.2f %s",
           $size, ( qw[ B KB MB GB TB PB EB] )[ $n ];
}
