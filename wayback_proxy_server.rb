# encoding: UTF-8

class WaybackProxyServer

  def initialize(*args)
    @opts = args.extract_options!
    @threads = []
  end

  def server
    @server ||= TCPServer.new(host, port)
  end

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
      else
        http_not_implemented
    end rescue nil
  end

  # Handle GET requests
  def get_request(uri)
    begin
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
        # content << "<!DOCTYPE html>\n<html><head><title>WHAt</title></head><body>THIS IS FOR THE BODY</body></html>"
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


  # def determine_content_type(uri)
  #   return :image if uri.path.match(/\.(png|gif|jpg|jpeg|bmp|svg)$/i)
  #   return :document if uri.path.match(/\.(doc|docx|xls|xlsx|csv|txt|pdf)$/i)
  #   return :media if uri.path.match(/\.(mp4|mp3|avi|wma|wmv|acc|m4a|ogg|mov|flv|mpg|mpeg)$/i)
  #   return :unknown
  # end
  # 
  # def get_wayback_response(uri)
  #   Wayback.get(uri, :first)
  # end


  def handle_error(m,e)
    puts "Error: #{m || 'unknown'}"
    e.backtrace.map{|l| puts "   #{l}"}
  end

  def default_opts; {'User-Agent' => WAYBACK_PROXY_USER_AGENT}; end
  def host; @opts[:host] || 'localhost'; end
  def port; @opts[:port] || 8888; end
  def max_redirects; WAYBACK_PROXY_MAX_REDIRECTS || 5; end
  def max_retries; WAYBACK_PROXY_MAX_RETRIES || 5; end


  def http_success; "HTTP/1.1 200 OK\r\n"; end
  def http_failure; "HTTP/1.1 404 Not Found\r\n"; end
  def http_not_implemented; "HTTP/1.1 501 Not Implemented\r\n"; end
  def http_too_many_redirects; "HTTP/1.1 504 Gateway Timeout\r\n"; end

end