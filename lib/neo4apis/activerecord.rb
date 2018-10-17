require 'neo4apis'
require 'ostruct'
require 'composite_primary_keys'

module Neo4Apis
  class ActiveRecord < Base
    batch_size 1000

    def self.model_importer(model_class, exceptions=[])
      if model_class.primary_key.is_a?(Array)
        relationship_name = model_class.table_name
        associations = model_class.reflect_on_all_associations

        importer model_class.name.to_sym do |object|
          from_node = object.send(associations[0].name)
          from_node = add_model_node from_node.class, from_node

          to_node = object.send(associations[1].name)

          puts 'add_model_relationship...'
          add_model_relationship relationship_name, from_node, to_node
        end
      else
        p "running #{model_class}"
        return if model_class.primary_key.nil?
        begin
        uuid model_class.name.to_sym, model_class.primary_key

        importer model_class.name.to_sym do |object|
          node = add_model_node model_class, object

          model_class.reflect_on_all_associations.each do |association_reflection|
            case association_reflection.macro
            when :belongs_to, :has_one
              if options[:"import_#{association_reflection.macro}"]
                referenced_object = object.send(association_reflection.name)
                add_model_relationship association_reflection.name, node, referenced_object if (referenced_object and not (exceptions.include? association_reflection.name.singularize.camelize))
              end
            when :has_many, :has_and_belongs_to_many
              if options[:"import_#{association_reflection.macro}"]
                object.send(association_reflection.name).each do |referenced_object|
                  add_model_relationship association_reflection.name, node, referenced_object if (referenced_object and not (exceptions.include? association_reflection.name.singularize.camelize))
                end
              end
            end
          end
        end
        rescue => e
          p "Error: #{e}"
        end
      end
    end

    def add_model_relationship(relationship_name, node, referenced_object)
      referenced_class = referenced_object.class
      referenced_node = add_model_node referenced_class, referenced_object

      add_relationship relationship_name, node, referenced_node
    end

    def add_model_node(model_class, object)
      object_data = OpenStruct.new

      object.class.column_names.each do |column_name|
        object_data.send("#{column_name}=", attribute_for_coder(object, column_name))
      end

      begin
        add_node model_class.name.to_sym, object_data, model_class.column_names
      rescue
        raise object_data.inspect + model_class.column_names.inspect 
      end 
    end

    def attribute_for_coder(object, column_name)
      column = object.class.columns_hash[column_name]
      if column.respond_to?(:cast_type)
        column.cast_type.type_cast_from_user(object.attributes[column_name])
      else
        value = object.attributes[column_name]
        value
      end
    end
  end
end
