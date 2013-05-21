class WaybackProxyServer

  def initialize(*args)
    @opts = args.extract_options!
    @opts[:host] ||= 'localhost'
    @opts[:port] ||= 8888

    @http_success = "HTTP/1.1 200 OK\r\n"
    @http_failure = "HTTP/1.1 404 Not Found\r\n\r\n"
    @http_too_many_redirects = "HTTP/1.1 504 Gateway Timeout\r\n" # Not one for looping, but we should give one as timeout from the proxy
    @threads = []
  end

  def server
    @server ||= TCPServer.new(@opts[:host], @opts[:port])
  end

  def run
    # This does not work for simutaneous requests, gets garbled.
    loop do
      # start a new thread with the request
      @threads << Thread.start(server.accept) do |session|
        begin
          request, resp, count = '', nil, 0
          # read entire request
          while r = session.gets
            break if r =~ /^\s*$/
            request << r.chomp
          end

          request, resp = request.lines.first, nil # first line

          # Get the URL from the request string
          uri = URI.parse(request.gsub(/^(GET|POST|HEAD|PUT|DELETE)/, '').gsub(/(\sHTTP.*)/, ''))
        rescue => err
          session.print(@http_failure)
          session.close
          Thread.current.exit
        end

        begin
          # Do process based on request type
          if request.match(/^GET/)
            resp = get_response(uri) rescue nil
          # elsif request.match(/^POST/)
          # elsif request.match(/^HEAD/)
          # elsif request.match(/^PUT/)
          # elsif request.match(/^DELETE/)
          else
            puts "dunno match? #{request}"
          end

          if resp
            session.print(resp)
          else
            session.print(@http_failure)
          end

        rescue Errno::EPIPE, Errno::ECONNRESET => err
          puts "RETRY (#{uri.to_s}): #{err}\n"

          unless count > 5
            count += 1
            retry
          else
            puts "ERROR : TOO MANY RETRYS"
            session.print(@http_failure)
          end

        rescue => err
          puts err.inspect
          puts "ERROR (#{uri.to_s}): #{err}\n"
          session.print(@http_failure)
        end

        session.close rescue nil

        Thread.current.exit
      end
    end
  end

  def get_response(uri,i=0)
    return @http_too_many_redirects if i > 5

    begin
      req = Net::HTTP::Get.new(uri.path, {'User-Agent' => WAYBACK_USER_AGENT})
      resp = Net::HTTP.start(uri.host, uri.port){|http| http.request(req)}
      content = ''

      case resp
        when Net::HTTPSuccess
          puts "success"
          content << @http_success
          resp.each_header {|h,v| content << h + ": " + v + "\r\n"}
          puts content.inspect
          content << "\r\n"
          # content << "THIS IS FOR THE BODY"
          content << resp.body
          content << "\r\n"
          return content

        when Net::HTTPRedirection
          puts "      - REDIRECT: #{resp['location']}\n"
          return get_response(URI.parse(resp['location']), i+1)

        else
          puts "ERR? #{resp}"
          return @http_failure
      end
    rescue => err
      puts "ERR2: #{err}"
      return @http_failure
    end
  end


end