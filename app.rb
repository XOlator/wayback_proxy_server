# encoding: UTF-8

# Wayback WiFi
# A X&O Lab Creative Project
# http://www.x-and-o.co/lab
#
# (C) 2013 X&O. All Rights Reserved
# License information: LICENSE.md


APP_ROOT = File.dirname(__FILE__)
WAYBACK_USER_AGENT = 'Wayback/0.1.0 <http://www.x-and-o.co/labs>'

Encoding.default_external = "UTF-8"
Encoding.default_internal = "UTF-8"

require "rubygems"
require "bundler"
Bundler.setup

requires = ['socket', 'net/http', 'uri', 'wayback', File.expand_path(APP_ROOT, 'wayback_proxy_server.rb')]
requires.each{|r| require r}


class Array
  def extract_options!; last.is_a?(::Hash) ? pop : {}; end unless defined? Array.new.extract_options!
end


server = WaybackProxyServer.new(:host => 'localhost', :port => 8888)
server.run