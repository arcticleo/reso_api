module RESO
  module API
    class QueryFormatter
      OPERATOR_MAP = {
        '>'  => 'gt',
        '>=' => 'ge',
        '<'  => 'lt',
        '<=' => 'le',
        '='  => 'eq',
        '!=' => 'ne'
      }.freeze

      OPERATOR_PATTERN = /\s*(>=|<=|!=|>|<|=)\s*/

      def self.format_value(value)
        case value
        when String         then "'#{value.gsub("'", "''")}'"
        when Integer        then value.to_s
        when Float          then value.to_s
        when Time, DateTime then value.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        when Date           then value.strftime('%Y-%m-%d')
        when TrueClass, FalseClass then value.to_s
        when NilClass       then 'null'
        else value.to_s
        end
      end

      def self.translate_operator(op)
        OPERATOR_MAP[op.strip] || raise(ArgumentError, "Unknown operator: #{op}")
      end
    end
  end
end
