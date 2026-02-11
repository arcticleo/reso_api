module RESO
  module API
    class WhereChain
      def initialize(query_builder)
        @query_builder = query_builder
      end

      def not(conditions)
        fragments = QueryConditions.parse(conditions, negate: true)
        fragments.each { |f| @query_builder.add_condition(f) }
        @query_builder
      end
    end
  end
end
