require 'active_record'
require 'active_support/inflector'
require 'thor'
require 'colorize'
require 'neo4apis/model_resolver'
require 'neo4apis/cli/base'

module Neo4Apis
  module CLI
    class ActiveRecord < CLI::Base
      include ModelResolver

      class_option :debug, type: :boolean, default: false, desc: 'Output debugging information'

      class_option :import_all_associations, type: :boolean, default: false, desc: 'Shortcut for --import-belongs-to --import-has-many --import-has-one'
      class_option :import_belongs_to, type: :boolean, default: nil
      class_option :import_has_one, type: :boolean, default: nil
      class_option :import_has_many, type: :boolean, default: nil

      class_option :identify_model, type: :boolean, default: false, desc: 'Identify table name, primary key, and foreign keys automatically'

      class_option :startup_environment, type: :string, default: './config/environment.rb', desc: 'Script that will be run before import.  Needs to establish an ActiveRecord connection'

      class_option :active_record_config_path, type: :string, default: './config/database.yml'
      class_option :active_record_environment, type: :string, default: 'development'

      desc 'tables MODELS_OR_TABLE_NAMES', 'Import specified SQL tables'
      def tables(*models_or_table_names)
        setup
	      tables = Array.wrap(models_or_table_names.map(&method(:get_model)))
        import_models_or_tables(tables) #constantize?
      end

      desc 'models MODELS_OR_TABLE_NAMES', 'Import specified ActiveRecord models'
      def models(*models_or_table_names)
        setup
        Rails.application.eager_load!
	      models = Array.wrap(models_or_table_names.map(&method(:get_model)))
        import_models_or_tables(models) #constantize?
      end

      desc 'all_models', 'Import SQL tables using defined models'
      def all_models
        setup
        Rails.application.eager_load!
        import_models_or_tables(*ApplicationRecord.descendants)#.collect{|model| model.name})
      end

      desc 'all_models_except EXCEPTIONS', 'Import all defined models except specified'
      def all_models_except(*exceptions)
        setup
        Rails.application.eager_load!
        puts exceptions
        all_models = *ApplicationRecord.descendants
        models_to_process = []
        for model in all_models
          unless exceptions.include? model.name
            models_to_process << model
          end
        end
        import_models_or_tables(models_to_process, exceptions)
      end

      desc 'models_with_internal_associations MODELS_OR_TABLE_NAMES', 'Import specified ActiveRecord models and their associations if the association model is in the included set of models'
      def models_with_internal_associations(*models_or_table_names)
        setup
	       models = Array.wrap(models_or_table_names.map(&method(:get_model)))
         #now create exception set based on all the models NOT in "models"
         exceptions = []
         Rails.application.eager_load!
         ApplicationRecord.descendants.each do |rails_model|
           exceptions << rails_model.name unless models.include? rails_model
         end
        import_models_or_tables(models, exceptions) #constantize?
      end

      private

      def debug_log(*messages)
        return unless options[:debug]
        puts(*messages)
      end

      def import_models_or_tables(models_or_table_names, exceptions=[])
        model_classes = Array.wrap(models_or_table_names) #.map(&method(:get_model))

        puts 'Importing tables: ' + model_classes.map(&:table_name).join(', ')

        model_classes.each do |model_class|
        #Rails.application.eager_load!
        #ApplicationRecord.descendants.each do |model_class|
          NEO4APIS_CLIENT_CLASS.model_importer(model_class, exceptions)
        end

        neo4apis_client.batch do
          model_classes.each do |model_class|
            puts "now directly importing: " + model_class.name
            begin
              query = model_class.all  #if this fails, that means the table is unavailable. Lets us skip crashing later down the road
              first_entry = query.first
            rescue
              puts "Error: Model " + model_class.name + " Does not have a table (or something else went wrong)! Skipping model to prevent errors"
              next
            end

            # Eager load association for faster import
            include_list = include_list_for_model(model_class)
            if include_list.present?
              filtered_include_list = []
              for association in include_list
                filtered_include_list << association unless exceptions.include? association.to_s.singularize.camelize
              end
              puts filtered_include_list #uncomment when testing to see if relationships are properly being included
              query = query.includes(*filtered_include_list) unless filtered_include_list.blank?
            end

            if query.primary_key.nil?
              puts "There's no primary key associated with this model. Skipping model to prevent errors"
              next
            else
              query.find_each do |object|
                neo4apis_client.import model_class.name.to_sym, object unless exceptions.include? object.class.to_s.singularize.camelize
              end
            end
          end
        end
      end

      def include_list_for_model(model_class)
        model_class.reflect_on_all_associations.map do |association_reflection|
          association_reflection.name.to_sym if (import_association?(association_reflection.macro))
        end.compact.tap do |include_list|
          debug_log 'include_list', include_list.inspect
        end
      end

      def setup
        if File.exist?(options[:startup_environment])
          require options[:startup_environment]
        else
          ::ActiveRecord::Base.establish_connection(active_record_config)
        end
      end

      NEO4APIS_CLIENT_CLASS = ::Neo4Apis::ActiveRecord

      def neo4apis_client
        @neo4apis_client ||= NEO4APIS_CLIENT_CLASS.new(specified_neo4j_session,
                                                       import_belongs_to: import_association?(:belongs_to),
                                                       import_has_one: import_association?(:has_one),
                                                       import_has_many: import_association?(:has_many),
                                                       import_has_and_belongs_to_many: import_association?(:has_and_belongs_to_many))
      end

      def import_association?(type)
        options[:"import_#{type}"].nil? ? options[:import_all_associations] : options[:"import_#{type}"]
      end


      def active_record_config
        require 'yaml'
        YAML.load(File.read(options[:active_record_config_path]))[options[:active_record_environment]]
      end

      def tables
        ::ActiveRecord::Base.connection.tables
      end
    end

    class Base < Thor
      desc 'activerecord SUBCOMMAND ...ARGS', 'methods of importing data automagically from Twitter'
      subcommand 'activerecord', CLI::ActiveRecord
    end
  end
end
