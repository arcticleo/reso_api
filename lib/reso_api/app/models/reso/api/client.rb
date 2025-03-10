module RESO
  module API
    class Client

      require 'net/http'
      require 'oauth2'
      require 'json'
      require 'tmpdir'

      attr_accessor :access_token, :client_id, :client_secret, :auth_url, :base_url, :scope, :osn

      def initialize(**opts)
        @access_token, @client_id, @client_secret, @auth_url, @base_url, @scope, @osn = opts.values_at(:access_token, :client_id, :client_secret, :auth_url, :base_url, :scope, :osn)
        validate!
      end

      def validate!
        if access_token.nil?
          raise 'Missing Client ID `client_id`' if client_id.nil?
          raise 'Missing Client Secret `client_secret`' if client_secret.nil?
          raise 'Missing Authentication URL `auth_url`' if auth_url.nil?
          raise 'Missing API Base URL `base_url`' if base_url.nil?
        else
          raise 'Missing API Base URL `base_url`' if base_url.nil?
        end
      end

      RESOURCE_KEYS = {
        media: "MediaKey",
        members: "MemberKey",
        offices: "OfficeKey",
        open_houses: "OpenHouseKey",
        properties: "ListingKey"
      }

      DETAIL_ENDPOINTS = {
        medium: "/Media",
        member: "/Member",
        office: "/Office",
        open_house: "/OpenHouse",
        property: "/Property"
      }

      FILTERABLE_ENDPOINTS = {
        media: "/Media",
        members: "/Member",
        offices: "/Office",
        open_houses: "/OpenHouse",
        properties: "/Property"
      }

      PASSTHROUGH_ENDPOINTS = {
        metadata: "/$metadata"
      }

      FILTERABLE_ENDPOINTS.keys.each do |method_name|
        define_method method_name do |*args, &block|
          filter = hash[:filter]
          filter = [filter, "OriginatingSystemName eq '#{osn}'"].compact.join(' and ') if osn.present?
          hash = args.first.is_a?(Hash) ? args.first : {}
          endpoint = FILTERABLE_ENDPOINTS[method_name]
          response = {}
          params = {
            "$select": hash[:select],
            "$filter": filter,
            "$top": hash[:top].presence,
            "$skip": hash[:skip],
            "$orderby": hash[:orderby].to_a.presence,
            "$skiptoken": hash[:skiptoken],
            "$expand": hash[:expand],
            "$count": hash[:count].to_s.presence,
            "$ignorenulls": hash[:ignorenulls].to_s.presence,
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

      def auth_token
        access_token.presence ? access_token : oauth2_token
      end

      def oauth2_client
        OAuth2::Client.new(
          client_id,
          client_secret,
          token_url: auth_url,
          scope: scope.presence,
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
        @oauth2_payload = oauth2_client.client_credentials.get_token('client_id' => client_id, 'client_secret' => client_secret, 'scope' => scope.presence)
        File.write(oauth2_token_path, @oauth2_payload.to_hash.to_json)
        return @oauth2_payload
      end

      def oauth2_token_path
        File.join(Dir.tmpdir, [base_url.parameterize, client_id, "oauth-token.json"].join("-"))
      end

      def oauth2_payload
        @oauth2_payload ||= get_oauth2_payload
      end

      def get_oauth2_payload
        if File.exist?(oauth2_token_path)
          persisted = File.read(oauth2_token_path)
          payload = OAuth2::AccessToken.from_hash(oauth2_client, JSON.parse(persisted))
        else
          payload = oauth2_client.client_credentials.get_token('client_id' => client_id, 'client_secret' => client_secret, 'scope' => scope.presence)
          File.write(oauth2_token_path, payload.to_hash.to_json)
        end
        return payload
      end

      def uri_for_endpoint endpoint
        return URI(endpoint).host ? URI(endpoint) : URI([base_url, endpoint].join)
      end

      def perform_call(endpoint, params, max_retries = 5, debug = false)
        uri = uri_for_endpoint(endpoint)
        params = params.presence || {}
        retries = 0

        query = params.present? ? URI.encode_www_form(params).gsub("+", " ") : ""
        uri.query && uri.query.length > 0 ? uri.query += '&' + query : uri.query = query
        return URI::decode(uri.request_uri) if params.dig(:$debug).present?

          begin
          req = Net::HTTP::Get.new(uri.request_uri)
          req['Authorization'] = "Bearer #{auth_token}"
          res = Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
            http.request(req)
          end
          response = JSON(res.body) rescue res.body
          if response.is_a?(String) && response.include?('Bad Gateway')
            puts "Error: Bad Gateway." if debug
            raise StandardError
          elsif response.is_a?(String) && response.include?('Unauthorized')
            puts "Error: Unauthorized." if debug
            fresh_oauth2_payload
            raise StandardError
          elsif response.is_a?(Hash) && response.has_key?("error")
            puts "Error: #{response.inspect}" if debug
            raise StandardError
          elsif response.is_a?(Hash) && response.has_key?("retry-after")
            puts "Error: Retrying in #{response["retry-after"].to_i}} seconds." if debug
            sleep response["retry-after"].to_i
            raise StandardError
          end
        rescue Net::ReadTimeout, StandardError
          if (retries += 1) <= max_retries
            sleep 5
            retry
          else
            raise
          end
        end
        return response
      end

      def entity_names
        doc = Nokogiri::XML(metadata)
        namespace = { 'edm' => 'http://docs.oasis-open.org/odata/ns/edm' }
        doc.xpath('//edm:EntityType', namespace).map { |node| node['Name'] }
      end

      def supported_expandables
        expandables_arr = []

        entity_names.each do |entity_name|
          success = try_expand(entity_name)
          expandables_arr << entity_name if success
        end

        expandables_arr.join(',').presence
      end

      def try_expand(entity_name)
        endpoint = '/Property'
        params = { '$expand' => entity_name }
        params['$filter'] = "OriginatingSystemName eq '#{osn}'" if osn.present?

        response = perform_call(endpoint, params, max_retries = 0)
        (!response.is_a?(Hash) || !response.key?('error')) && response['statusCode'].blank? && response['status'].blank?
      rescue StandardError
        false
      end
    end
  end
end
