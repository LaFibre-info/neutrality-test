# neutrality-test
test your ISP neutrality
version 1.1.5

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

           GET [<label>] 4|6 <url> <...>         performs a download test from <url> in IPv4 ou IPv6
           PUT [<label>] 4|6 <size> <url> <...>  performs an upload test of <size> bytes to <url> in IPv4 ou IPv6
           PRINT <rest of line>         print the rest of the line to stdout
           TIME <value>                 change the timeout of following tests to <value> seconds. 0 = no timeout
           # <rest of line>             comment, ignore rest of the line

        <label>: a word or a phrase between quotes (") (whitespace = space or tab)
        <url>: a valid url. Accepted schemes are : http, https, ftp
        <...>: additional arguments passed directly to the curl command (for instance --insecure)
        <size> format : <value>
          <value> = <number> or <number>[KMGT]
          K, M, G,T denote: Kilo, Mega, Giga and Tera (each are x1000 increment not 1024)

  see tests.txt, multi-isp.txt and def.txt for sample tests.
