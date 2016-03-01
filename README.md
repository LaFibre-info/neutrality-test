# neutrality-test
test your ISP neutrality

    neutrality-test [options]
     Options:
       -debug           display debug informations
       -help            brief help message
       -4               IPv4 only
       -6               IPv6 only
       -csv             output results as a 'database ready' table
       -test "<test>"   performs the given test
       -size <size>     change size
       -ul              perform only upload tests
       -dl              perform only download tests
       -time <value>    timeout each test after <value> seconds
       -server <server> specify server (dns name or IP)

    <test> format = "IP PORT PROTO EXT DIR"
      IP = 4 or 6
      PORT = a valid TCP port
      PROT = http or https
      EXT  = any file extention with a leading dot (ex: .zip)
      DIR  = GET or POST
    <size> format = <value> or <value>/<value>
      <value> = <number> or <number>[KMGT]
      a single <value> set both upload & download size to the same value
      a double <value>/<value> set download (1st) and upload (2nd) distinct sizes
      K, M, G,T denote: Kilo, Mega, Giga and Tera
      for instance "2G/20M" set 2GB download size and 20MB upload size
