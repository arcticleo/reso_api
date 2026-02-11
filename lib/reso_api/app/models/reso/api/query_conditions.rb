module RESO
  module API
    class QueryConditions
      class << self
        def parse(args, negate: false)
          case args
          when Hash
            from_hash(args, negate: negate)
          when Array
            from_array(args, negate: negate)
          else
            raise ArgumentError, "Unsupported where argument type: #{args.class}"
          end
        end

        private

        def from_hash(hash, negate: false)
          hash.map do |field, value|
            fragment = case value
            when Array
              format_in(field, value)
            when Range
              format_range(field, value)
            else
              format_eq(field, value)
            end

            negate ? negate_fragment(field, value, fragment) : fragment
          end
        end

        def from_array(array, negate: false)
          template = array.first
          bindings = array[1..]

          if bindings.first.is_a?(Hash)
            result = substitute_named_placeholders(template, bindings.first)
          else
            result = substitute_positional_placeholders(template, bindings)
          end

          negate ? ["not (#{result})"] : [result]
        end

        def format_eq(field, value)
          if value.is_a?(String)
            leading = value.start_with?('%') && !value.start_with?('\%')
            trailing = value.end_with?('%') && !value.end_with?('\%')

            if leading || trailing
              return format_string_match(field, value, leading, trailing)
            end

            # Unescape literal \% at boundaries for exact match
            if value.start_with?('\%') || value.end_with?('\%')
              value = value.sub(/\A\\%/, '%').sub(/\\%\z/, '%')
            end
          end

          "#{field} eq #{QueryFormatter.format_value(value)}"
        end

        def format_string_match(field, value, leading, trailing)
          inner = value.dup
          inner = inner[1..] if leading
          inner = inner[0..-2] if trailing

          # Unescape literal \% at boundaries
          inner = inner.sub(/\A\\%/, '%')
          inner = inner.sub(/\\%\z/, '%')

          formatted = QueryFormatter.format_value(inner)

          if leading && trailing
            "contains(#{field},#{formatted})"
          elsif leading
            "endswith(#{field},#{formatted})"
          else
            "startswith(#{field},#{formatted})"
          end
        end

        def format_in(field, values)
          formatted = values.map { |v| QueryFormatter.format_value(v) }.join(',')
          "#{field} in (#{formatted})"
        end

        def format_range(field, range)
          parts = []
          parts << "#{field} ge #{QueryFormatter.format_value(range.begin)}" if range.begin
          if range.end
            op = range.exclude_end? ? 'lt' : 'le'
            parts << "#{field} #{op} #{QueryFormatter.format_value(range.end)}"
          end
          parts.join(' and ')
        end

        def negate_fragment(field, value, fragment)
          case value
          when Array
            # Expand NOT IN to individual ne conditions
            value.map { |v| "#{field} ne #{QueryFormatter.format_value(v)}" }.join(' and ')
          when String
            if fragment.start_with?('contains(', 'startswith(', 'endswith(')
              "not #{fragment}"
            else
              "#{field} ne #{QueryFormatter.format_value(value)}"
            end
          else
            "#{field} ne #{QueryFormatter.format_value(value)}"
          end
        end

        def substitute_positional_placeholders(template, values)
          result = template.dup
          values.each do |value|
            result.sub!(QueryFormatter::OPERATOR_PATTERN) do |match|
              op = match.strip
              " #{QueryFormatter.translate_operator(op)} "
            end
            result.sub!('?', QueryFormatter.format_value(value))
          end
          result
        end

        def substitute_named_placeholders(template, bindings)
          result = template.dup
          result.gsub!(QueryFormatter::OPERATOR_PATTERN) do |match|
            op = match.strip
            " #{QueryFormatter.translate_operator(op)} "
          end
          bindings.each do |name, value|
            result.gsub!(":#{name}", QueryFormatter.format_value(value))
          end
          result
        end
      end
    end
  end
end
