require 'fluent/plugin/output'
require 'net/http'
require 'uri'
require 'json'

module Fluent
  module Plugin
    class BatchHttpOutput < Output
      Fluent::Plugin.register_output('batch_http', self)

      helpers :compat_parameters, :formatter

      DEFAULT_BUFFER_TYPE = 'memory'
      DEFAULT_FORMAT_TYPE = 'json'

      desc 'The endpoint URL to send data to'
      config_param :endpoint_url, :string

      desc 'The HTTP method to use'
      config_param :http_method, :enum, list: [:post, :put], default: :post

      desc 'Additional HTTP headers to send with the request'
      config_param :headers, :hash, default: {}

      desc 'Authentication username'
      config_param :username, :string, default: nil, secret: true

      desc 'Authentication password'
      config_param :password, :string, default: nil, secret: true

      desc 'Timeout in seconds for the HTTP request'
      config_param :timeout, :time, default: 10

      desc 'Maximum number of retries for HTTP request failures'
      config_param :max_retries, :integer, default: 3

      desc 'Backoff strategy for retries (constant, exponential)'
      config_param :retry_strategy, :enum, list: [:constant, :exponential], default: :exponential

      desc 'Initial retry interval in seconds'
      config_param :retry_interval, :time, default: 1

      desc 'Maximum retry interval in seconds'
      config_param :max_retry_interval, :time, default: 60

      config_section :buffer do
        config_set_default :@type, DEFAULT_BUFFER_TYPE
        config_set_default :chunk_keys, ['tag']
      end

      config_section :format do
        config_set_default :@type, DEFAULT_FORMAT_TYPE
      end

      def configure(conf)
        compat_parameters_convert(conf, :buffer, :formatter)
        super
        @uri = URI.parse(@endpoint_url)
        @formatter = formatter_create
      end

      def multi_workers_ready?
        true
      end

      def format(tag, time, record)
        @formatter.format(tag, time, record)
      end

      def write(chunk)
        body = build_request_body(chunk)
        send_request_with_retries(body)
      end

      private

      def build_request_body(chunk)
        events = []
        chunk.each do |time, record|
          events << record
        end
        events.to_json
      end

      def send_request_with_retries(body)
        retries = 0
        begin
          response = send_request(body)
          unless response.is_a?(Net::HTTPSuccess)
            raise "HTTP request failed with code #{response.code}: #{response.message}"
          end
          return true
        rescue => e
          if retries < @max_retries
            retries += 1
            wait_time = calculate_retry_interval(retries)
            log.warn "Failed to send request to #{@endpoint_url}, retrying in #{wait_time} seconds. Error: #{e.message}"
            sleep wait_time
            retry
          else
            log.error "Failed to send request to #{@endpoint_url} after #{@max_retries} retries. Error: #{e.message}"
            raise
          end
        end
      end

      def calculate_retry_interval(retry_count)
        case @retry_strategy
        when :constant
          @retry_interval
        when :exponential
          interval = @retry_interval * (2 ** (retry_count - 1))
          [interval, @max_retry_interval].min
        end
      end

      def send_request(body)
        http = Net::HTTP.new(@uri.host, @uri.port)
        http.use_ssl = @uri.scheme == 'https'
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        request = case @http_method
                  when :post
                    Net::HTTP::Post.new(@uri.request_uri)
                  when :put
                    Net::HTTP::Put.new(@uri.request_uri)
                  end

        request.body = body
        request.content_type = 'application/json'
        
        @headers.each do |key, value|
          request[key] = value
        end

        if @username && @password
          request.basic_auth(@username, @password)
        end

        http.request(request)
      end
    end
  end
end 