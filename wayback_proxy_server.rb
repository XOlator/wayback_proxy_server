# encoding: UTF-8

class WaybackProxyServer

  # TODO: ...
  #   - SSL support
  #   - POST requests
  #   - PUT requests
  #   - HEAD requests
  #   - DELETE requests

  def initialize(*args)
    @opts = args.extract_options!
    @threads = []
  end

  def server
    @server ||= TCPServer.new(host, port)
  end

  # Core server compontent that includes loop with Thread requests.
  def run
    loop do
      Thread.start(server.accept) do |session|
        begin
          request, resp = '', nil
          Thread.current[:redirect_count] = 0

          while (r = session.gets)
            break if r =~ /^\s*$/
            request << r.chomp
          end

          # Get the method and URL from the request string
          http_request = request.lines.first # first line
          puts http_request
          Thread.current[:request_method] = http_request.gsub(/^([A-Z]+)(.*)$/i, '\1').downcase.to_sym rescue nil
          uri = URI.parse(http_request.gsub(/^([A-Z]+)/, '').gsub(/(\sHTTP.*)/, ''))

        rescue
          handle_error(__method__, err)
          session.write(http_failure)
          session.close
          Thread.current.exit
        end

        begin
          resp = fetch(uri)
          session.write(resp)

        rescue Errno::EPIPE, Errno::ECONNRESET => err
          unless count > max_retries
            count += 1
            retry
          else
            handle_error(__method__, err)
            session.write(http_failure)
          end

        rescue => err
          handle_error(__method__, err)
          session.write(http_failure)
        end

        session.close rescue nil
        Thread.current.exit
      end
    end
  end

  # Method to fetch a URI, determine method for request, and handle certain errors.
  def fetch(uri)
    return http_too_many_redirects if Thread.current[:redirect_count] > max_redirects

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
      else
        http_not_implemented
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
      puts uri
      req = Net::HTTP::Get.new(uri.path, default_opts.merge({}))
      resp = Net::HTTP.start(uri.host, uri.port){|http| http.request(req)}
      parse_response(resp)
    rescue => err
      handle_error(__method__, err)
      http_failure
    end
  end

  # Handle POST requests
  def post_request
    http_not_implemented
  end

  # Handle HEAD requests
  def head_request
    http_not_implemented
  end

  # Handle PUT requests
  def put_request
    http_not_implemented
  end

  # Handle DELETE requests
  def delete_request
    http_not_implemented
  end

  # Handle CONNECT requests
  def connect_request
    http_not_implemented
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
        http_failure
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
    begin
      list = get_wayback_list(uri)
      if list[:dates].length > 0
        d = list[t] if [:first_date,:last_date].include?(t)
        d ||= list[:first_date] # default to first date
        URI.parse(list[:dates][d][:uri])
      else
        uri
      end
    rescue
      uri
    end
  end

  # Get the list of available archived pages
  def get_wayback_list(uri)
    # TODO: Nice place to add caching (HINT HINT REDIS)
    Wayback.list(uri)
  end

  # Echo out error information and backtrace.
  def handle_error(m,e)
    puts "Error: #{e} in #{m || 'unknown'}" # if DEBUG
    e.backtrace.map{|l| puts "   #{l}"} if DEBUG
  end

  # Default options
  def default_opts; {'User-Agent' => WAYBACK_PROXY_USER_AGENT}; end
  def host; @opts[:host] || 'localhost'; end
  def port; @opts[:port] || 8888; end
  def max_redirects; WAYBACK_PROXY_MAX_REDIRECTS || 5; end
  def max_retries; WAYBACK_PROXY_MAX_RETRIES || 5; end

  # HTTP status messages
  def http_success; "HTTP/1.1 200 OK\r\n"; end
  def http_failure; "HTTP/1.1 404 Not Found\r\n"; end
  def http_not_implemented; "HTTP/1.1 501 Not Implemented\r\n"; end
  def http_too_many_redirects; "HTTP/1.1 504 Gateway Timeout\r\n"; end

end