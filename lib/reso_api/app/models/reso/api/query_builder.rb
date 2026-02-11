module RESO
  module API
    class QueryBuilder
      include Enumerable

      DEFAULT_PROPERTIES_SCOPE = "StandardStatus in ('Active','Pending')"

      def initialize(client:, resource:)
        @client = client
        @resource = resource
        @conditions = []
        @select_fields = nil
        @order_clauses = nil
        @limit_value = nil
        @offset_value = nil
        @includes_values = nil
        @count_flag = false
        @unscoped_flag = false
        @loaded = false
        @records = nil
      end

      # --- Chainable methods ---

      def where(conditions = nil)
        if conditions.nil?
          return WhereChain.new(clone_builder)
        end

        builder = clone_builder
        fragments = QueryConditions.parse(conditions)
        fragments.each { |f| builder.add_condition(f) }
        builder
      end

      def select(*fields)
        if fields.first.is_a?(Proc) || (fields.empty? && block_given?)
          return super
        end

        builder = clone_builder
        builder.instance_variable_set(:@select_fields, fields.flatten.map(&:to_s))
        builder
      end

      def order(*args)
        builder = clone_builder
        clauses = args.flat_map do |arg|
          case arg
          when Hash
            arg.map { |field, dir| "#{field} #{dir}" }
          when String
            [arg]
          else
            [arg.to_s]
          end
        end
        builder.instance_variable_set(:@order_clauses, clauses)
        builder
      end

      def limit(value)
        builder = clone_builder
        builder.instance_variable_set(:@limit_value, value)
        builder
      end

      def offset(value)
        builder = clone_builder
        builder.instance_variable_set(:@offset_value, value)
        builder
      end

      def includes(*names)
        builder = clone_builder
        builder.instance_variable_set(:@includes_values, names.flatten.map(&:to_s))
        builder
      end

      def unscoped
        builder = clone_builder
        builder.instance_variable_set(:@unscoped_flag, true)
        builder
      end

      # --- Terminal methods ---

      def find(key)
        endpoint = Client::DETAIL_ENDPOINTS[@resource.to_s.singularize.to_sym]
        raise ArgumentError, "Unknown resource: #{@resource}" unless endpoint
        @client.send(:perform_call, "#{endpoint}('#{key}')", nil)
      end

      def find_by(conditions)
        builder = where(conditions).limit(1)
        builder.load
        builder.records.first
      end

      def first(n = nil)
        if n
          builder = limit(n)
          builder.load
          builder.records
        else
          builder = limit(1)
          builder.load
          builder.records.first
        end
      end

      def count
        builder = clone_builder
        builder.instance_variable_set(:@count_flag, true)
        builder.instance_variable_set(:@limit_value, 1)
        response = builder.execute_raw
        response['@odata.totalCount'].to_i
      end

      def each(&block)
        if block_given?
          execute_with_pagination(&block)
        else
          to_a.each
        end
      end

      def find_each(batch_size: 200, &block)
        builder = clone_builder
        builder.instance_variable_set(:@limit_value, batch_size)
        builder.execute_with_pagination(&block)
      end

      def to_a
        load
        @records
      end

      def to_ary
        to_a
      end

      def reload
        @loaded = false
        @records = nil
        self
      end

      def inspect
        load
        @records.inspect
      end

      def size
        to_a.size
      end

      def length
        to_a.length
      end

      def empty?
        to_a.empty?
      end

      def [](index)
        to_a[index]
      end

      # --- Internal ---

      def add_condition(fragment)
        @conditions << fragment
        @loaded = false
        @records = nil
        self
      end

      protected

      attr_reader :records

      def load
        return if @loaded
        response = execute_raw
        @records = response['value'].is_a?(Array) ? response['value'] : []
        @loaded = true
      end

      def execute_raw
        endpoint = Client::FILTERABLE_ENDPOINTS[@resource]
        raise ArgumentError, "Unknown resource: #{@resource}" unless endpoint

        params = build_params
        @client.send(:perform_call, endpoint, params)
      end

      def execute_with_pagination(&block)
        endpoint = Client::FILTERABLE_ENDPOINTS[@resource]
        raise ArgumentError, "Unknown resource: #{@resource}" unless endpoint

        params = build_params
        response = @client.send(:perform_call, endpoint, params)
        if response['value'].is_a?(Array)
          response['value'].each(&block)
        end

        while (next_link = response['@odata.nextLink']).present?
          response = @client.send(:perform_call, next_link, nil)
          if response['value'].is_a?(Array)
            response['value'].each(&block)
          end
        end
      end

      def build_params
        params = {}
        params[:"$filter"] = build_filter
        params[:"$select"] = @select_fields.join(',') if @select_fields
        params[:"$orderby"] = @order_clauses.join(',') if @order_clauses
        params[:"$top"] = @limit_value if @limit_value
        params[:"$skip"] = @offset_value if @offset_value
        params[:"$expand"] = @includes_values.join(',') if @includes_values
        params[:"$count"] = 'true' if @count_flag
        params.compact
      end

      def build_filter
        filters = @conditions.dup

        # Apply OSN filter if configured and not already present
        if @client.osn.present? && filters.none? { |f| f.include?('OriginatingSystemName') }
          filters.unshift("OriginatingSystemName eq '#{@client.osn}'")
        end

        # Apply default scope for properties unless overridden
        if @resource == :properties && !@unscoped_flag
          unless filters.any? { |f| f.include?('StandardStatus') }
            filters << DEFAULT_PROPERTIES_SCOPE
          end
        end

        filter_string = filters.join(' and ')
        filter_string.presence
      end

      def clone_builder
        builder = QueryBuilder.new(client: @client, resource: @resource)
        builder.instance_variable_set(:@conditions, @conditions.dup)
        builder.instance_variable_set(:@select_fields, @select_fields&.dup)
        builder.instance_variable_set(:@order_clauses, @order_clauses&.dup)
        builder.instance_variable_set(:@limit_value, @limit_value)
        builder.instance_variable_set(:@offset_value, @offset_value)
        builder.instance_variable_set(:@includes_values, @includes_values&.dup)
        builder.instance_variable_set(:@count_flag, @count_flag)
        builder.instance_variable_set(:@unscoped_flag, @unscoped_flag)
        builder
      end
    end
  end
end
