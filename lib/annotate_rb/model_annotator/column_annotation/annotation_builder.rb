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
          is_primary_key = is_column_primary_key?(@model, @column.name)

          table_indices = @model.retrieve_indexes_from_table
          column_indices = table_indices.select { |ind| ind.columns.include?(@column.name) }
          column_defaults = @model.column_defaults

          if @model.connection.is_a?(ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter)
            @column = enhance_column(@model, @column)
          end

          column_attributes = AttributesBuilder.new(@column, @options, is_primary_key, column_indices, column_defaults).build
          formatted_column_type = TypeBuilder.new(@column, @options, column_defaults).build

          display_column_comments = @options[:with_comment] && @options[:with_column_comments]
          col_name = if display_column_comments && @model.with_comments? && @column.comment
            "#{@column.name}(#{@column.comment.gsub(/\n/, '\\n')})"
          else
            @column.name
          end

          _component = ColumnComponent.new(col_name, @max_size, formatted_column_type, column_attributes)
        end

        private

        def enhance_column(model, column)
          if column.virtual?
            enhance_virtual_column(model, column)
          elsif column.sql_type.match?(/\Aenum\b/)
            enhance_enum_column(column)
          else
            column
          end
        end

        def enhance_virtual_column(model, column)
          column = column.dup
          generation_expression = model.connection.query_value(<<~SQL.squish, "SCHEMA").gsub("\\'", "'").inspect
            SELECT generation_expression FROM information_schema.columns
            WHERE table_schema = database()
              AND table_name = '#{model.table_name}'
              AND column_name = '#{column.name}'
          SQL

          column.define_singleton_method(:default_function) { generation_expression }
          column
        end

        def enhance_enum_column(column)
          column = column.dup
          enum_values = column.sql_type.scan(/\(([^()]*)\)/)

          column.define_singleton_method(:type) { "enum" }
          column.define_singleton_method(:limit) { enum_values }
          column
        end

        # TODO: Simplify this conditional
        def is_column_primary_key?(model, column_name)
          if model.primary_key
            if model.primary_key.is_a?(Array)
              # If the model has multiple primary keys, check if this column is one of them
              if model.primary_key.collect(&:to_sym).include?(column_name.to_sym)
                return true
              end
            elsif column_name.to_sym == model.primary_key.to_sym
              # If model has 1 primary key, check if this column is it
              return true
            end
          end

          false
        end
      end
    end
  end
end
