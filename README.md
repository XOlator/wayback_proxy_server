# Wayback Proxy Server

Proxy server to fetch web traffic and return results from Archive.org's Wayback Machine.


## Getting Started

Wayback WiFi can be run in a few ways

[details on commamds]

### Adding OpenSSL Certificates

If you enable SSL support (-s or --ssl), Wayback Proxy Server will look for the key .ssl/wayback.key and .ssl/wayback.crt.

To generate these, do the following:

mkdir .ssl
openssl genrsa -out .ssl/wayback.key 2048
openssl req -new -key .ssl/wayback.key -out .ssl/wayback.csr
openssl x509 -req -days 365 -in .ssl/wayback.csr -out .ssl/wayback.crt -signkey .ssl/wayback.key


## License

(C) 2013-2014 [X&O][x-o]. http://www.xolator.com

Read the [LICENSE.md][license] for more information

[x-o]: http://www.xolator.com
[license]: LICENSE.md