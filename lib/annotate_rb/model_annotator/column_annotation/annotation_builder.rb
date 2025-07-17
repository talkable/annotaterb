# frozen_string_literal: true

module AnnotateRb
  module ModelAnnotator
    module ColumnAnnotation
      class AnnotationBuilder
        def initialize(column, model, max_size, options)
          @column = column
          @model = model
          @max_size = max_size
          @options = options
        end

        def build
          @column = enhance_column(@model, @column)

          column_attributes = @model.built_attributes[@column.name]
          formatted_column_type = TypeBuilder.new(@column, @options, @model.column_defaults).build

          display_column_comments = @options[:with_comment] && @options[:with_column_comments]
          display_column_comments &&= @model.with_comments? && @column.comment
          position_of_column_comment = @options[:position_of_column_comment] || Options::FLAG_OPTIONS[:position_of_column_comment] if display_column_comments

          max_attributes_size = @model.built_attributes.values.map { |v| v.join(", ").length }.max

          _component = ColumnComponent.new(
            column: @column,
            max_name_size: @max_size,
            type: formatted_column_type,
            attributes: column_attributes,
            position_of_column_comment: position_of_column_comment,
            max_attributes_size: max_attributes_size
          )
        end

        private

        def enhance_column(model, column)
          case model.connection.adapter_name
          when "PostgreSQL"
            return enhance_postgresql_enum_column(model, column.dup) if column.type == :enum
          when "Trilogy"
            return enhance_mysql_virtual_column(model, column.dup) if column.virtual?
            return enhance_mysql_enum_column(column.dup) if column.sql_type.match?(/\Aenum\b/)
          end

          column
        end

        def enhance_mysql_virtual_column(model, column)
          generation_expression = model.connection.query_value(<<~SQL.squish, "SCHEMA").gsub("\\'", "'").inspect
            SELECT generation_expression FROM information_schema.columns
            WHERE table_schema = database()
              AND table_name = '#{model.table_name}'
              AND column_name = '#{column.name}'
          SQL

          column.define_singleton_method(:default_function) { generation_expression }
          column
        end

        def enhance_mysql_enum_column(column)
          enum_values = column.sql_type.scan(/\(([^()]*)\)/)

          column.define_singleton_method(:type) { "enum" }
          column.define_singleton_method(:limit) { enum_values }
          column
        end

        def enhance_postgresql_enum_column(model, column)
          enum_values = model.connection.select_values("SELECT unnest(enum_range(NULL::#{column.sql_type}))::text")

          column.define_singleton_method(:limit) { enum_values }
          column
        end
      end
    end
  end
end
