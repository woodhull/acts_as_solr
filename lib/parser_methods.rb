module ActsAsSolr #:nodoc:
  
  module ParserMethods
    
    protected    
    
    # Method used by mostly all the ClassMethods when doing a search
    def parse_query(query=nil, options={}, models=nil)
      valid_options = [:offset, :limit, :facets, :models, :results_format, :order, :scores, :operator, :handler, :filter_queries, :sort, :find_options, :morelikethis]
      query_options = {}
      #set the default handler
      options = {:handler => 'standard', :filter_queries => [] }.update(options)
      return if query.nil?
      raise "Invalid parameters: #{(options.keys - valid_options).join(',')}" unless (options.keys - valid_options).empty?
      begin
        Deprecation.validate_query(options)
        query_options[:query] = query
        query_options[:start] = options[:offset]
        query_options[:rows] = options[:limit]
        query_options[:operator] = options[:operator]
        query_options[:filter_queries] = options[:filter_queries]
        
        # first steps on the facet parameter processing
        if options[:facets]
          query_options[:facets] = {}
          query_options[:facets][:limit] = -1  # TODO: make this configurable
          query_options[:facets][:sort] = options[:facets][:sort] || false
          query_options[:facets][:mincount] = options[:facets][:mincount] || 0
          query_options[:facets][:mincount] = 1 if options[:facets][:zeros] == false
          query_options[:facets][:fields] = options[:facets][:fields] if options[:facets][:fields]
          query_options[:filter_queries] << options[:facets][:browse] if options[:facets][:browse]
          query_options[:facets][:queries] = options[:facets][:queries] if options[:facets][:queries]
        end

        if options[:morelikethis]
          query_options[:mlt] = options[:morelikethis]
        end
        
        if models.nil?
          models = "#{solr_configuration[:type_field]}:#{self.class_name}"
          field_list = solr_configuration[:primary_key_field]
        else
          field_list = "id"
        end
        
        query_options[:field_list] = [field_list, 'score']

        query_options[:filter_queries] << models

        #either an empty array or passed in
        query_options[:sort] = options[:sort] || []

        #if options[:order]
        #  # TODO: bad hack, come back and fix this.
        #  query_options[:sort] << {replace_types([order], false)[0] => :descending }
        #end

        #filters should be unique.
        query_options[:filter_queries] = query_options[:filter_queries].flatten.uniq

        if options[:handler]
          case options[:handler]
          when 'standard'
            result = ActsAsSolr::Post.execute(Solr::Request::Standard.new(query_options))
          when 'dismax'
            result = ActsAsSolr::Post.execute(Solr::Request::Dismax.new(query_options))
          when 'morelikethis'
            result = ActsAsSolr::Post.execute(Solr::Request::MoreLikeThis.new(query_options))
          end
        end
      #rescue
      #  raise "There was a problem executing your search: #{$!}"
      end
      result
    end
    
    # Parses the data returned from Solr
    def parse_results(solr_data, options = {})
      results = {
        :docs => [],
        :total => 0
      }
      configuration = {
        :format => :objects
      }
      results.update(:facets => {'facet_fields' => []}) if options[:facets]
      return SearchResults.new(results) if solr_data.total_hits == 0
      
      configuration.update(options) if options.is_a?(Hash)
      result = []
      if options[:multi]
        docs = solr_data.hits
        if options[:results_format] == :objects
          docs.each{|doc| k = doc.fetch('id').to_s.split(':'); result << k[0].constantize.find_by_id(k[1])}
        elsif options[:results_format] == :ids
          docs.each{|doc| result << {"id"=>doc.values.pop.to_s}}
        end
      else
        ids = solr_data.hits.collect {|doc| doc["#{solr_configuration[:primary_key_field]}"]}.flatten
        conditions = [ "#{self.table_name}.#{primary_key} in (?)", ids ]
        if options[:find_options]
          find_options = {:conditions => conditions}.update(options[:find_options])
        else
          find_options = {:conditions => conditions}
        end   
        result = configuration[:format] == :objects ? reorder(self.find(:all, find_options), ids) : ids
      end

      add_scores(result, solr_data) if configuration[:format] == :objects && options[:scores]
      
      results.update(:facets => solr_data.data['facet_counts']) if options[:facets]
      results.update({:docs => result, :total => solr_data.total_hits, :max_score => solr_data.max_score})
      SearchResults.new(results)
    end
    
    # Reorders the instances keeping the order returned from Solr
    def reorder(things, ids)
      ordered_things = []
      ids.each do |id|
        record = things.find {|thing| record_id(thing).to_s == id.to_s} 
        raise "Out of sync! The id #{id} is in the Solr index but missing in the database!" unless record
        ordered_things << record
      end
      ordered_things
    end
    
    # Adds the score to each one of the instances found
    def add_scores(results, solr_data)
      with_score = []
      solr_data.docs.each do |doc|
        with_score.push([doc["score"], 
          results.find {|record| record_id(record).to_s == doc["#{solr_configuration[:primary_key_field]}"].to_s }])
      end
      with_score.each do |score,object| 
        class <<object; attr_accessor :solr_score; end
        object.solr_score = score
      end
    end
  end

end