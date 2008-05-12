module ActsAsSolr #:nodoc:
  
  module InstanceMethods

    # Solr id is <class.name>:<id> to be unique across all models
    def solr_id
      "#{self.class.name}:#{record_id(self)}"
    end

    # saves to the Solr index
    def solr_save
      return true unless configuration[:if] 
      if evaluate_condition(configuration[:if], self) 
        logger.debug "solr_save: #{self.class.name} : #{record_id(self)}"
        solr_add to_solr_doc
        solr_commit if configuration[:auto_commit]
        true
      else
        solr_destroy
      end
    end

    # remove from index
    def solr_destroy
      logger.debug "solr_destroy: #{self.class.name} : #{record_id(self)}"
      solr_delete solr_id
      solr_commit if configuration[:auto_commit]
      true
    end

    # finds records that solr thinks are similar to the current record
    def solr_more_like_this
      @solr_more_like_this ||= self.class.find_by_solr("id:#{self.class.class_name}\\:#{self.id}", :handler => 'morelikethis', :limit => '5', :morelikethis => {:field_list => ['title,description']})
    end

    # convert instance to Solr document
    def to_solr_doc
      logger.debug "to_solr_doc: creating doc for class: #{self.class.name}, id: #{record_id(self)}"
      doc = Solr::Document.new
      doc.boost = validate_boost(configuration[:boost]) if configuration[:boost]
      
      doc << {:id => solr_id,
              solr_configuration[:type_field] => self.class.name,
              solr_configuration[:primary_key_field] => record_id(self).to_s}


      add_fields(doc)
      add_spellword(doc) if configuration[:spellcheck]
      logger.debug doc.to_xml.to_s
      return doc
    end

    def add_fields(doc)
      self.class.configuration[solr_classname(self.class)][:fields].each do |key, field|
        add_field(doc, self, self.class, field)
      end
    end

    def add_field(doc, obj, klass, field, stack = [], multivalued = false)
      # add the field to the document, but only if it's not the id field
      # or the type field (from single table inheritance), since these
      # fields have already been added above.
      if field.name.to_s != obj.class.primary_key && field.name.to_s != "type"
        if field.index_type == :association
          associated_klass = field.name.to_s.singularize
          case obj.class.reflect_on_association(field.name).macro
          when :has_many, :has_and_belongs_to_many
            records = self.send(field.name).to_a
            unless records.empty?
              if records.first.respond_to?(:to_solr_doc) && stack.size < 6 && records.first.class.configuration[solr_classname(records.first.class)][:fields] && !records.first.class.configuration[solr_classname(records.first.class)][:fields].empty?
                stack << field.name
                records.each do | ar_record |
                  ar_record.class.configuration[solr_classname(ar_record.class)][:fields].each do |key, record_field|
                    add_field(doc, ar_record, ar_record.class, record_field, stack, true)
                  end
                end
                stack.pop
              else
                data = ""
                records.each{|r| data << r.attributes.inject([]){|k,v| k << "#{v.first}=#{ERB::Util.html_escape(v.last)}"}.join(" ")}
                doc["#{associated_klass}_t"] = data
              end
            end
          when :has_one, :belongs_to
            record = obj.send(field.name)
            unless record.nil?  
              if record.respond_to?(:to_solr_doc) && stack.size < 6 && record.class.configuration[solr_classname(record.class)][:fields] && !record.class.configuration[solr_classname(record.class)][:fields].empty?
                stack << field.name
                record.class.configuration[solr_classname(record.class)][:fields].each do |key, record_field|
                  add_field(doc, record, record.class, record_field, stack, true)
                end
                stack.pop
              else
                data = record.attributes.inject([]){|k,v| k << "#{v.first}=#{ERB::Util.html_escape(v.last)}"}.join(" ")
                doc["#{associated_klass}_t"] = data
              end
            end
          end

        else #not an association
          if field.value
           value = field.value.call(obj) 
          else
            value = obj.send("#{field.name}_for_solr")
          end
          # This next line ensures that e.g. nil dates are excluded from the
          # document, since they choke Solr. Also ignores e.g. empty strings,
          # but these can't be searched for anyway:
          # http://www.mail-archive.com/solr-dev@lucene.apache.org/msg05423.html
          unless value.nil? || value.to_s.strip.empty?
            [value].flatten.each do |v|
              field_name = field.name
              field_name = "#{stack.join('_')}_#{field_name}" if stack.size > 0
              solr_field = Solr::Field.new("#{field_name}" => ERB::Util.html_escape(value))
              solr_field.boost = field.boost
              doc << solr_field
            end
          end
        end
      end
    end




    def add_spellword(doc)
      if configuration[:spellcheck].is_a?(Array)
        spellword = configuration[:spellcheck].collect {| field_name | self.send("#{field_name}_for_solr")}.join(' ')
        doc << Solr::Field.new("spellword" => spellword.downcase)
      end
    end
    
    def validate_boost(boost)
      if boost.class != Float || boost < 0
        logger.warn "The boost value has to be a float and posisive, but got #{boost}. Using default boost value."
        return solr_configuration[:default_boost]
      end
      boost
    end
    
    def condition_block?(condition)
      condition.respond_to?("call") && (condition.arity == 1 || condition.arity == -1)
    end
    
    def evaluate_condition(condition, field)
      case condition
        when Symbol: field.send(condition)
        when String: eval(condition, binding)
        else
          if condition_block?(condition)
            condition.call(field)
          else
            raise(
              ArgumentError,
              "The :if option has to be either a symbol, string (to be eval'ed), proc/method, or " +
              "class implementing a static validation method"
            )
          end
        end
    end
  end
end