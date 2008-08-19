module ActsAsSolr
  class Field
      def initialize
        @aliases = []
        @boost = 1.0
        @indexed = true
        @stored = false
        @tokenized = true
        @sortable = false
        @multivalued = false
        @include = {}
        @index_type = :text
        @known_as = nil
        @value = nil
        @facet_label = nil
      end

      def attr_name(name = nil)
        @attr_name = name.to_sym if name
        @indexed_name = @attr_name unless @indexed_name
        @attr_name
      end

      alias :attr_name= :attr_name
      alias :name :attr_name

      # is method_name already listed in instance_methods with a signature lacking an arg, accept it
      # self.instance_methods

      def indexed_name(name = nil)
        @indexed_name = name.to_sym if name
        @indexed_name
      end

      alias :indexed_name= :indexed_name

      attr_accessor :index_type, :aliases, :boost, :known_as, :value


      def indexed(i = nil)
        @indexed = i unless i.nil?
        @indexed
      end

      alias :indexed= :indexed
      alias :indexed? :indexed

      def stored(s = nil)
        @stored = s unless s.nil?
        @stored
      end

      alias :stored= :stored
      alias :stored? :stored

      def tokenized(t = nil)
        @tokenized = t unless t.nil?
        @tokenized
      end

      alias :tokenized= :tokenized
      alias :tokenized? :tokenized

      def sortable(s = nil)
        @sortable = s unless s.nil?
        @sortable
      end

      alias :sortable= :sortable
      alias :sortable? :sortable

      def multivalued(s = nil)
        @multivalued = s unless s.nil?
        @multivalued
      end

      alias :multivalued= :multivalued
      alias :multivalued? :multivalued

      def facet_label(s = nil)
        @facet_label = s unless s.nil?
        @facet_label
      end

      alias :facet_label= :facet_label

      def facet_display_value(s = nil)
        @facet_display_value = s unless s.nil?
        @facet_display_value
      end

      alias :facet_display_value= :facet_display_value

      def include(name = nil, opts = {})
        if name
          field = Field.new
          field.attr_name = name.to_sym
          field.indexed_name = opts[:indexed_name].to_sym if opts[:indexed_name]
          field.aliases = opts[:aliases] if opts[:aliases]
          field.boost = opts[:boost] if opts[:boost]
          field.indexed = opts[:indexed] unless opts[:indexed].nil?
          field.stored = opts[:stored] unless opts[:stored].nil?
          field.tokenized = opts[:tokenized] unless opts[:tokenized].nil?
          field.sortable = opts[:sortable] unless opts[:sortable].nil?
          field.facet_label = opts[:facet_label] unless opts[:facet_label].nil?
          field.facet_display_value = opts[:facet_display_value] unless opts[:facet_display_value].nil?

          # override parameters if a block was provided
          yield field if block_given?

          @include[name.to_sym] = field
        end
        @include
      end
    end
  end

