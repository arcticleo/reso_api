module RESO
  module API
    class Client

      require 'net/http'
      require 'oauth2'
      require 'json'
      require 'tmpdir'

      attr_accessor :client_id, :client_secret, :auth_url, :base_url

      def initialize(**opts)
        @client_id, @client_secret, @auth_url, @base_url = opts.values_at(:client_id, :client_secret, :auth_url, :base_url)
        validate!
      end

      def validate!
        raise 'Missing Client ID `client_id`' if client_id.nil?
        raise 'Missing Client Secret `client_secret`' if client_secret.nil?
        raise 'Missing Authentication URL `auth_url`' if auth_url.nil?
        raise 'Missing API Base URL `base_url`' if base_url.nil?
      end

      RESOURCE_KEYS = {
        media: "MediaKey",
        members: "MemberKey",
        offices: "OfficeKey",
        properties: "ListingKey"
      }

      DETAIL_ENDPOINTS = {
        medium: "/Media",
        member: "/Member",
        office: "/Office",
        property: "/Property"
      }

      FILTERABLE_ENDPOINTS = {
        media: "/Media",
        members: "/Member",
        offices: "/Office",
        properties: "/Property"
      }

      PASSTHROUGH_ENDPOINTS = {
        metadata: "/$metadata"
      }

      FILTERABLE_ENDPOINTS.keys.each do |method_name|
        define_method method_name do |*args, &block|
          hash = args.first.is_a?(Hash) ? args.first : {}
          endpoint = FILTERABLE_ENDPOINTS[method_name]
          response = {}
          params = {
            "$select": hash[:select],
            "$filter": hash[:filter],
            "$top": hash[:top] ||= 100,
            "$skip": hash[:skip] ||= 0,
            "$orderby": hash[:orderby] ||= RESOURCE_KEYS[method_name],
            "$skiptoken": hash[:skiptoken],
            "$expand": hash[:expand],
            "$count": hash[:count].to_s.presence,
            "$debug": hash[:debug]
          }.compact
          if !block.nil?
            response = perform_call(endpoint, params)
            
            if response["value"].class.eql?(Array)
              hash[:batch] ? block.call(response["value"]) : response["value"].each{|hash| block.call(hash)} 
            end

            while (next_link = response["@odata.nextLink"]).present?
              response = perform_call(next_link, nil)
              
              if response["value"].class.eql?(Array)
                hash[:batch] ? block.call(response["value"]) : response["value"].each{|hash| block.call(hash)} 
              end
            end
          else
            return perform_call(endpoint, params)
          end
        end
      end

      DETAIL_ENDPOINTS.keys.each do |method_name|
        define_method method_name do |*args|
          endpoint = "#{DETAIL_ENDPOINTS[method_name]}('#{args.try(:first)}')"
          perform_call(endpoint, nil)
        end
      end

      PASSTHROUGH_ENDPOINTS.keys.each do |method_name|
        define_method method_name do |*args|
          endpoint = PASSTHROUGH_ENDPOINTS[method_name]
          perform_call(endpoint, nil)
        end
      end

      def oauth2_client
        OAuth2::Client.new(
          client_id,
          client_secret,
          token_url: auth_url,
          scope: "api",
          grant_type: "client_credentials"
        )
      end

      def oauth2_token
        payload = oauth2_payload
        token = JWT.decode(payload.token, nil, false)
        exp_timestamp = Hash(token.try(:first))["exp"].to_s
        expiration = DateTime.strptime(exp_timestamp, '%s').utc rescue DateTime.now.utc
        if expiration > DateTime.now.utc
          return payload.token
        else
          @oauth2_payload = fresh_oauth2_payload
          return @oauth2_payload.token
        end
      end

      def fresh_oauth2_payload
        @oauth2_payload = oauth2_client.client_credentials.get_token
        File.write(oauth2_token_path, @oauth2_payload.to_hash.to_json)
        return @oauth2_payload
      end

      def oauth2_token_path
        File.join(Dir.tmpdir, [base_url.parameterize, "-oauth-token.json"].join)
      end

      def oauth2_payload
        @oauth2_payload ||= get_oauth2_payload
      end

      def get_oauth2_payload
        if File.exist?(oauth2_token_path)
          persisted = File.read(oauth2_token_path)
          payload = OAuth2::AccessToken.from_hash(oauth2_client, JSON.parse(persisted))
        else
          payload = oauth2_client.client_credentials.get_token
          File.write(oauth2_token_path, payload.to_hash.to_json)
        end
        return payload
      end

      def uri_for_endpoint endpoint
        return URI(endpoint).host ? URI(endpoint) : URI([base_url, endpoint].join)
      end

      def perform_call(endpoint, params)
        uri = uri_for_endpoint(endpoint)
        retries = 0
        if params.present?
          query = params.present? ? URI.encode_www_form(params).gsub("+", " ") : ""
          uri.query && uri.query.length > 0 ? uri.query += '&' + query : uri.query = query
          return URI::decode(uri.request_uri) if params.dig(:$debug).present?
        end
        begin
          req = Net::HTTP::Get.new(uri.request_uri)
          req['Authorization'] = "Bearer #{oauth2_token}"
          res = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
            http.request(req)
          end
          response = JSON(res.body) rescue res.body
          if response.is_a?(String) && response.include?('Bad Gateway')
            raise StandardError
          elsif response.is_a?(String) && response.include?('Unauthorized')
            fresh_oauth2_payload
            raise StandardError
          elsif response.is_a?(Hash) && response.has_key?("error")
            raise StandardError
          end
        rescue Net::ReadTimeout, StandardError
          if (retries += 1) <= 5
            sleep 10
            retry
          else
            raise
          end
        end
        return response
      end

    end
  end
end
