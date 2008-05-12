class Solr::Response::MoreLikeThis < Solr::Response::Select
  def initialize(ruby_code)
    super
    @response = @data['response']
    if @response  == 'nil' || @response == nil
      @response = {'numFound' => 0, 'docs' => []}
    end
    raise "response section missing" unless @response.kind_of? Hash
  end

  def hits
    @response['docs']
  end

  def total_hits
    @response['numFound']
  end

  def start
    @response['start']
  end
  
  def max_score
    @response['maxScore']
  end

  def each
    @response['docs'].each {|hit| yield hit}
  end
end