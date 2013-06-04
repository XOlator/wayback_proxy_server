# encoding: UTF-8

# Wayback WiFi
# A X&O Lab Creative Project
# http://www.x-and-o.co/lab
#
# (C) 2013 X&O. All Rights Reserved
# License information: LICENSE.md


APP_ROOT = File.dirname(__FILE__)

Encoding.default_external = "UTF-8"
Encoding.default_internal = "UTF-8"

require "rubygems"
require "bundler"
Bundler.setup

requires = ['openssl', 'optparse', 'socket', 'net/http', 'uri', 'wayback', 'redis', File.expand_path(APP_ROOT, 'wayback_proxy_server.rb'), File.expand_path(APP_ROOT, 'version.rb')]
requires.each{|r| require r}

WAYBACK_PROXY_USER_AGENT = "Wayback/#{WaybackProxyServerVersion.to_s} <http://www.x-and-o.co/labs>"
WAYBACK_PROXY_MAX_REDIRECTS = 5
WAYBACK_PROXY_MAX_RETRIES = 5

# Ensure the proper options are set on start
options = {:port => 8888, :cache_db => 1}

OptionParser.new do |opts|
  opts.banner = "Usage: app.rb [options]"
  opts.on("-h H", "--host H", String, "Host IP/domain") {|v| options[:host] = v}
  opts.on("-p P", "--port P", Integer, "Port") {|v| options[:port] = v}
  opts.on("-c DB", "--cache-db DB", Integer, "Cache Database") {|v| options[:cache_db] = v}
  opts.on("--debug", "Debug Mode") {|v| DEBUG = true}
  opts.on("-d", "--daemon", "Daemon Mode") {|v| options[:daemon] = true}
  opts.on("-s", "--ssl", "Allow SSL") {|v| options[:ssl] = {}}
end.parse!
DEBUG ||= false


raise "Host IP/domain required" if options[:host].nil? || options[:host] == ''


# SSL Certificate
if options[:ssl]
  options[:ssl][:key] = File.join(APP_ROOT, '.ssl', 'server.key')# if File.exists?(File.expand_path(APP_ROOT, '.ssl/wayback.key'))
  options[:ssl][:cert] = File.join(APP_ROOT, '.ssl', 'server.pem')# if File.exists?(File.expand_path(APP_ROOT, '.ssl/wayback.crt'))
end


# Hack for array extract_options! stype
class Array
  def extract_options!; last.is_a?(::Hash) ? pop : {}; end unless defined? Array.new.extract_options!
end


# Cache setup
begin
  # $wayback_cache = Diskcached.new(File.join(APP_ROOT, 'cache'))
  # $wayback_cache.flush if DEBUG # ensure caches are empty on startup
  $wayback_cache = Redis.new(:db => options[:cache_db])
  $wayback_cache.flushdb if DEBUG # flush db on start
rescue
  nil
end

# Use our User-agent (Wayback config)
Wayback.configure do |c|
  c.connection_options[:headers][:user_agent] = WAYBACK_PROXY_USER_AGENT
end


# --- BEGIN ---

result = Proc.new{|opts, cache|
   server = WaybackProxyServer.new(:host => opts[:host], :port => opts[:port], :ssl => opts[:ssl], :cache => $wayback_cache)
   server.run
}

begin
  if options[:daemon]
    puts "Forking process..."
    p = fork { result.call(options) }
    sleep 2
    s = Process.getpgid(p) rescue nil
    if s
      Process.detach(p)
      File.open('./proxy.pid', "w") {|f| f.write p}
      puts "   running as #{p}."
    else
      puts "   did not start"
    end
  else
    result.call(options)
  end
rescue => err
  puts "ERROR: #{err}"
  err.backtrace.map{|l| puts "   #{l}"} if DEBUG
end
