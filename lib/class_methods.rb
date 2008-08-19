require File.dirname(__FILE__) + '/common_methods'
require File.dirname(__FILE__) + '/parser_methods'

module ActsAsSolr #:nodoc:

  module ClassMethods
    include CommonMethods
    include ParserMethods

    # Index an attribute.
    def index_attr(*attr_names)
      # input is either a list or a symbol with options
      if attr_names.last.is_a?(Hash)
        opts = attr_names.pop if attr_names.last.is_a?(Hash)
      else
        opts = {}
      end

      attr_names.each do | attr_name |
        configuration[solr_classname(self)][:fields] ||= {}
        field = ::ActsAsSolr::Field.new
        field.attr_name = attr_name.to_sym
        field.indexed_name = opts[:indexed_name].to_sym if opts[:indexed_name]
        field.aliases = opts[:aliases] if opts[:aliases]
        field.boost = opts[:boost] if opts[:boost]
        field.indexed = opts[:indexed] unless opts[:indexed].nil?
        field.stored = opts[:stored] unless opts[:stored].nil?
        field.tokenized = opts[:tokenized] unless opts[:tokenized].nil?
        field.sortable = opts[:sortable] unless opts[:sortable].nil?
        field.index_type =  opts[:type] unless opts[:type].nil?
        field.multivalued =  opts[:multivalued] unless opts[:multivalued].nil?
        field.known_as =  opts[:known_as] unless opts[:known_as].nil?
        field.value =  opts[:value] unless opts[:value].nil?
        field.facet_display_value = opts[:facet_display_value] unless opts[:value].nil?
        # override parameters if a block was provided
        yield field if block_given?

        configuration[solr_classname(self)][:fields][attr_name] = field

        if field.index_type == :association
          process_association(field)
        else
          get_field_value(field)
        end
      end
    end

    def solr_indexable?
     configuration[:index]
    end


    # Finds instances of a model. Terms are ANDed by default, can be overwritten
    # by using OR between terms
    #
    # Here's a sample (untested) code for your controller:
    #
    #  def search
    #    results = Book.find_by_solr params[:query]
    #  end
    #
    # You can also search for specific fields by searching for 'field:value'
    #
    # ====options:
    # offset:: - The first document to be retrieved (offset)
    # limit:: - The number of rows per page
    # order:: - Orders (sort by) the result set using a given criteria:
    #
    #             Book.find_by_solr 'ruby', :order => 'description asc'
    #
    # field_types:: This option is deprecated and will be obsolete by version 1.0.
    #               There's no need to specify the :field_types anymore when doing a
    #               search in a model that specifies a field type for a field. The field
    #               types are automatically traced back when they're included.
    #
    #                 class Electronic < ActiveRecord::Base
    #                   acts_as_solr :fields => [{:price => :range_float}]
    #                 end
    #
    # facets:: This option argument accepts the following arguments:
    #          fields:: The fields to be included in the faceted search (Solr's facet.field)
    #          query:: The queries to be included in the faceted search (Solr's facet.query)
    #          zeros:: Display facets with count of zero. (true|false)
    #          sort:: Sorts the faceted resuls by highest to lowest count. (true|false)
    #          browse:: This is where the 'drill-down' of the facets work. Accepts an array of
    #                   fields in the format "facet_field:term"
    #
    # Example:
    #
    #   Electronic.find_by_solr "memory", :facets => {:zeros => false, :sort => true,
    #                                                 :query => ["price:[* TO 200]",
    #                                                            "price:[200 TO 500]",
    #                                                            "price:[500 TO *]"],
    #                                                 :fields => [:category, :manufacturer],
    #                                                 :browse => ["category:Memory","manufacturer:Someone"]}
    #
    # scores:: If set to true this will return the score as a 'solr_score' attribute
    #          for each one of the instances found. Does not currently work with find_id_by_solr
    #
    #            books = Book.find_by_solr 'ruby OR splinter', :scores => true
    #            books.records.first.solr_score
    #            => 1.21321397
    #            books.records.last.solr_score
    #            => 0.12321548
    #
    def find_by_solr(query, options={})
      data = parse_query(query, options)
      return parse_results(data, options) if data
    end

    # Finds instances of a model and returns an array with the ids:
    #  Book.find_id_by_solr "rails" => [1,4,7]
    # The options accepted are the same as find_by_solr
    #
    def find_id_by_solr(query, options={})
      data = parse_query(query, options)
      return parse_results(data, {:format => :ids}) if data
    end

    # This method can be used to execute a search across multiple models:
    #   Book.multi_solr_search "Napoleon OR Tom", :models => [Movie]
    #
    # ====options:
    # Accepts the same options as find_by_solr plus:
    # models:: The additional models you'd like to include in the search
    # results_format:: Specify the format of the results found
    #                  :objects :: Will return an array with the results being objects (default). Example:
    #                               Book.multi_solr_search "Napoleon OR Tom", :models => [Movie], :results_format => :objects
    #                  :ids :: Will return an array with the ids of each entry found. Example:
    #                           Book.multi_solr_search "Napoleon OR Tom", :models => [Movie], :results_format => :ids
    #                           => [{"id" => "Movie:1"},{"id" => Book:1}]
    #                          Where the value of each array is as Model:instance_id
    #
    def multi_solr_search(query, options = {})
      models = "(#{solr_configuration[:type_field]}:#{self.class_name}"
      options[:models].each{|m| models << " OR type:"+m.to_s} if options[:models].is_a?(Array)
      options.update(:results_format => :objects) unless options[:results_format]
      data = parse_results(parse_query(query, options, models<<")"), options.update({:multi => ''}))
    end

    # returns the total number of documents found in the query specified:
    #  Book.count_by_solr 'rails' => 3
    #
    def count_by_solr(query, options = {})
      data = parse_query(query, options)
      data.total_hits
    end

    # It's used to rebuild the Solr index for a specific model.
    #  Book.rebuild_solr_index
    #
    # If batch_size is greater than 0, adds will be done in batches.
    # NOTE: If using sqlserver, be sure to use a finder with an explicit order.
    # Non-edge versions of rails do not handle pagination correctly for sqlserver
    # without an order clause.
    #
    # If a finder block is given, it will be called to retrieve the items to index.
    # This can be very useful for things such as updating based on conditions or
    # using eager loading for indexed associations.
    def rebuild_solr_index(batch_size=0, &finder)
      finder ||= lambda { |ar, options| ar.find(:all, options.merge({:order => self.primary_key})) }

      if batch_size > 0
        items_processed = 0
        limit = batch_size
        offset = 0
        begin
          items = finder.call(self, {:limit => limit, :offset => offset})
          add_batch = items.collect { |content| content.to_solr_doc }

          if items.size > 0
            solr_add add_batch
            solr_commit
          end

          items_processed += items.size
          logger.debug "#{items_processed} items for #{self.class_name} have been batch added to index."
          offset += items.size
        end while items.nil? || items.size > 0
      else
        items = finder.call(self, {})
        items.each { |content| content.solr_save }
        items_processed = items.size
      end
      solr_optimize
      rebuild_solr_spellcheck
      logger.debug items_processed > 0 ? "Index for #{self.class_name} has been rebuilt" : "Nothing to index for #{self.class_name}"
    end

    def rebuild_solr_spellcheck
      ActsAsSolr::Post.execute(Solr::Request::Spellcheck.new(:query => 'rebuild', :command => 'rebuild'))
    end

    def get_spelling_suggestions(query)
       ActsAsSolr::Post.execute(Solr::Request::Spellcheck.new(:query => query.downcase,  :suggestion_count => 2)).suggestions
    end


    private

    def process_association(association)
      r = self.reflect_on_association(association.name)
      if association.known_as
        parent_name = association.known_as
      else
        parent_name = self.class_name.downcase.intern
      end
      
      unless r.nil?
        begin
          assoc_klass = r.klass
          add_save_to_included_class(parent_name, assoc_klass)
        rescue ActiveRecord::StatementInvalid=>err
          puts "acts_as_solr had problems loading the class #{r.class_name}, skipping the association.\n#{err.message}"
          logger.error "acts_as_solr had problems loading the class #{r.class_name}, skipping the association.\n#{err.message}"
        end
      end
    end

    def add_save_to_included_class(parent_name, klass)
      case klass.reflect_on_association(parent_name).macro
      when :has_one, :belongs_to
        klass.class_eval <<-end_eval
          after_save    :#{parent_name}_solr_association_save
          after_destroy :#{parent_name}_solr_association_destroy

          def #{parent_name}_solr_association_save
            #{parent_name}.solr_save if #{parent_name}
          end
          def #{parent_name}_solr_association_destroy
            #{parent_name}.solr_save if #{parent_name}
          end
        end_eval

      when :has_many, :has_and_belongs_to_many
         klass.class_eval <<-end_eval
          after_save    :#{parent_name}_solr_association_save
          after_destroy :#{parent_name}_solr_association_destroy

          def #{parent_name}_solr_association_save
            #{parent_name}.each{|o| o.solr_save } if #{parent_name}
          end

          def #{parent_name}_solr_association_destroy
            #{parent_name}.each{|o| o.solr_save } if #{parent_name}
          end
        end_eval
      end
    end

    def get_field_value(field)

      define_method("#{field.name}_for_solr".to_sym) do
        begin
          value = self[field.name] || self.instance_variable_get("@#{field.name.to_s}".to_sym) || self.send(field.name.to_sym)
          case field.index_type
            # format dates properly; return nil for nil date
          when :date
            if value
              value.respond_to?(:utc) ? value.utc.strftime("%Y-%m-%dT%H:%M:%SZ") : value.strftime("%Y-%m-%dT%H:%M:%SZ")
            else
              nil
            end
          when :association: nil
            else value
          end
        rescue
          value = ''
          logger.debug "There was a problem getting the value for the field '#{field.name}': #{$!}"
        end
      end
    end

    def process_fields(raw_field)
      if raw_field.respond_to?(:each)
        raw_field.each do |field|
          next if configuration[:exclude_fields].include?(field)
          get_field_value(field)
        end
      end
    end



  end
  
end