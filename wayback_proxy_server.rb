# encoding: UTF-8

class WaybackProxyServer

  CR   = "\x0d"
  LF   = "\x0a"
  CRLF = "\x0d\x0a"


  # TODO: ...
  #   - SSL support
  #   - POST requests
  #   - PUT requests
  #   - HEAD requests
  #   - DELETE requests

  def initialize(*args)
    @opts = args.extract_options!
    @cache = @opts[:cache]
    @threads = []

    puts "Starting Wayback Server on #{host}:#{port}..." if DEBUG
  end

  def server
    return @server unless @server.nil?

    @server = TCPServer.new(host, port)
    begin
      if ssl_configured?
        # context = OpenSSL::SSL::SSLContext.new
        # context.verify_mode = OpenSSL::SSL::VERIFY_NONE
        # context.cert = OpenSSL::X509::Certificate.new( File.read(@opts[:ssl][:cert]) )
        # context.key = OpenSSL::PKey::RSA.new( File.read(@opts[:ssl][:key]) )
        # @sslserver = OpenSSL::SSL::SSLServer.new(@server, context)
        # # @sslserver.start_immediately = true
        # @server = @sslserver
        # puts "...using OpenSSL" if DEBUG
      end
    rescue => err
      puts "OpenSSL Error: #{err}"
    end
    @server
  end

  def ssl_configured?
    false # File.exists?(@opts[:ssl][:cert]) and File.exists?(@opts[:ssl][:key])
  end

  def whitelist
    @whitelist ||= File.readlines(File.join(APP_ROOT, 'whitelist.txt')).to_a.map{|v| v.match(/^(\r)?\n$/) ? nil : v.gsub(/(\r)?\n/m, '')}.compact rescue []
  end

  # Wrapper for cache, if configured
  def cache(key)
    if @cache
      begin
        sha_key = Digest::SHA1.hexdigest(key)
        result = @cache.get(sha_key) rescue nil
        unless result
          result = Proc.new{ yield }.call
          @cache.set(sha_key, result)
        end
        result
      rescue => err
        puts "Caching Error: #{key} :: #{err}"
        result = Proc.new{ yield }.call
      end
    else
      result = Proc.new{ yield }.call
    end

    result
  end

  # Core server compontent that includes loop with Thread requests.
  def run
    loop do
      Thread.start(server.accept) do |session|
        Thread.current[:session] = session

        begin
          request, resp = '', nil
          Thread.current[:redirect_count] = 0

          while (r = Thread.current[:session].gets)
            break if r =~ /^\s*$/
            request << r.chomp
          end

          Thread.current[:request] = request

          # Get the method and URL from the request string
          http_request = request.lines.first # first line
          Thread.current[:request_method] = http_request.gsub(/^([A-Z]+)(.*)$/i, '\1').downcase.to_sym rescue nil

          uri = URI.parse(http_request.gsub(/^([A-Z]+)/, '').gsub(/(\sHTTP.*)/, '')) rescue nil

        rescue => err
          handle_error(__method__, err)
          Thread.current[:session].write(http_error(:failure))
          Thread.current[:session].close
          Thread.current.exit
        end

        begin
          resp = fetch(uri)
          Thread.current[:session].write(resp)

        rescue Errno::EPIPE, Errno::ECONNRESET => err
          unless count > max_retries
            count += 1
            retry
          else
            handle_error(__method__, err)
            Thread.current[:session].write(http_error(:failure))
          end

        rescue => err
          handle_error(__method__, err)
          Thread.current[:session].write(http_error(:failure))
        end

        Thread.current[:session].close rescue nil
        Thread.current.exit
      end
    end
  end

  # Method to fetch a URI, determine method for request, and handle certain errors.
  def fetch(uri)
    return http_error(:bad_request) if uri.nil?
    return http_error(:too_many_redirects) if Thread.current[:redirect_count] > max_redirects

    puts "Fetch: #{Thread.current[:request_method]}: #{uri}" if DEBUG

    case Thread.current[:request_method]
      when :get
        get_request(uri)
      when :post
        post_request(uri)
      when :put
        put_request(uri)
      when :head
        head_request(uri)
      when :delete
        delete_request(uri)
      when :connect
        connect_request(uri)
      when :options
        options_request(uri)
      when :trace
        trace_request(uri)
      else
        http_error(:not_implemented)
    end rescue nil
  end

  # Handle GET requests
  def get_request(uri)
    # Get Wayback URI if URI seems like it would be an item that is archived.
    begin
      if !uri.host.match(/archive\.org$/i) && determine_page_type(uri) == :unknown
        uri = get_wayback_uri(uri, :first_date)
      end
    rescue => err
      handle_error(__method__, err)
    end

    # GET request
    begin
      cache("get:#{uri}") do
        req = Net::HTTP::Get.new(uri.path, default_opts.merge({}))
        resp = Net::HTTP.start(uri.host, uri.port){|http| http.request(req)}
        parse_response(resp)
      end
    rescue => err
      handle_error(__method__, err)
      http_error(:failure)
    end
  end

  # Handle POST requests
  def post_request
    puts "POST not implemented: #{uri}" if DEBUG
    http_error(:not_implemented)
  end

  # Handle HEAD requests
  def head_request
    puts "HEAD not implemented: #{uri}" if DEBUG
    http_error(:not_implemented)
  end

  # Handle PUT requests
  def put_request
    puts "PUT not implemented: #{uri}" if DEBUG
    http_error(:not_implemented)
  end

  # Handle DELETE requests
  def delete_request
    puts "DELETE not implemented: #{uri}" if DEBUG
    http_error(:not_implemented)
  end

  # Handle CONNECT requests
  def connect_request(uri)
    if @opts[:allow_ssl]
      begin
       reqhost, reqport = uri.to_s.split(":", 2)

        begin
          os = TCPSocket.new(reqhost, reqport)
          Thread.current[:session].write(http_success)
        rescue => err
          puts ("CONNECT #{reqhost}:#{reqport}: failed `#{err.message}'")
          Thread.current[:session].write(http_error(:bad_gateway))
        ensure
          Thread.current[:session].write("\r\n") # Flush headers
        end

        begin
          Timeout::timeout(5) {
            while fds = IO::select([Thread.current[:session], os],nil,nil,5000)
              if fds[0].member?(Thread.current[:session])
                buf = Thread.current[:session].sysread(1024)
                os.syswrite(buf)
              elsif fds[0].member?(os)
                buf = os.sysread(1024)
                Thread.current[:session].syswrite(buf)
              end
            end
          }
        rescue Timeout::Error
          nil
        rescue => err
          handle_error(__method__, err)
        ensure
          os.close
        end

      rescue => err
        handle_error(__method__, err)
        nil
      end
    else
      http_error(:failure)
    end
  end

  # Handle OPTIONS requests
  def options_request(uri)
    puts "OPTIONS not implemented: #{uri}" if DEBUG
    http_error(:not_implemented)
  end

  # Handle TRACE requests
  def trace_request(uri)
    puts "TRACE not implemented: #{uri}" if DEBUG
    http_error(:not_implemented)
  end


  # Parse the Net::HTTP response
  def parse_response(resp,i=0)
    case resp
      when Net::HTTPSuccess
        content = http_success

        # Get Headers
        resp.each_header do |h,v|
          next if ['transfer-encoding', 'connection'].include?(h.downcase)
          content << h + ": " + v + "\r\n"
        end

        content << "\r\n"
        content << resp.body
        content << "\r\n"
        content

      when Net::HTTPRedirection
        Thread.current[:redirect_count] += 1
        new_uri = URI.parse(resp['location'])
        fetch(new_uri)

      else
        http_error(:failure)
    end
  end

  # Check what possible page_type a uri might be based on it's path.
  def determine_page_type(uri)
    return :image if uri.path.match(/\.(png|gif|jpg|jpeg|bmp|svg|ico)$/i)
    return :document if uri.path.match(/\.(doc|docx|xls|xlsx|csv|txt|pdf|md)$/i)
    return :media if uri.path.match(/\.(mp4|mp3|avi|wma|wmv|acc|m4a|ogg|mov|flv|mpg|mpeg)$/i)
    return :file if uri.path.match(/\.(css|js|xml|rss|rdf|json)$/i)
    return :unknown
  end


  # Get the URI for the Wayback page, if available
  def get_wayback_uri(uri,t=:first_date)
    cache("wayback:#{uri}:#{t}") do
      begin
        if whitelisted?(uri)
          uri
        else
          list = Wayback.list(uri)
          if list[:dates].length > 0
            d = list[t] if [:first_date,:last_date].include?(t)
            d ||= list[:first_date] # default to first date
            URI.parse(list[:dates][d][:uri])
          else
            uri
          end
        end
      rescue => err
        uri
      end
    end
  end

  # Echo out error information and backtrace.
  def handle_error(m,err)
    puts "Error: #{err} in #{m || 'unknown'}" # if DEBUG
    err.backtrace.map{|l| puts "   #{l}"} if DEBUG
  end

  def whitelisted?(uri)
    whitelist.each{|v| return true if uri.to_s.match(Regexp.new(Regexp.escape(v), true))}
    return false
  end

  # Default options
  def default_opts; {'User-Agent' => WAYBACK_PROXY_USER_AGENT}; end
  def host; @opts[:host] || 'localhost'; end
  def port; @opts[:port] || 8888; end
  def max_redirects; WAYBACK_PROXY_MAX_REDIRECTS || 5; end
  def max_retries; WAYBACK_PROXY_MAX_RETRIES || 5; end

  # HTTP status messages
  def http_success; "HTTP/1.1 200 OK\r\n"; end
  def http_bad_request; "HTTP/1.1 400 Bad Request\r\n"; end
  def http_failure; "HTTP/1.1 404 Not Found\r\n"; end
  def http_not_implemented; "HTTP/1.1 501 Not Implemented\r\n"; end
  def http_bad_gateway; "HTTP/1.1 503 Bad Gateway\r\n"; end
  def http_too_many_redirects; "HTTP/1.1 504 Gateway Timeout\r\n"; end

  def http_error(s)
    str = send("http_#{s}")
    i = str.gsub(/^(.*)(\d{3})(.*)$/m, '\2')
    str << "\r\n"
    str << File.read(File.join(APP_ROOT,"pages/#{i.to_s}.html")) rescue ':('
    str
  end

end