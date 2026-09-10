require 'nokogiri'

module CbetaSearch
  # 讀取 Manticore 轉檔流程產出的 data/manticore-xml/*.xml (xmlpipe2 格式)，
  # 逐份 document yield 成 Hash，供 Elasticsearch 匯入。
  #
  # text.xml 約 1.3GB、notes.xml 約 2GB，因此不整份載入 DOM，
  # 改為逐行累積單一 <sphinx:document> 再解析。
  class ManticoreXmlReader
    def initialize(path, integer_fields: [], array_integer_fields: [])
      @path = path
      @integer_fields = integer_fields.to_a
      @array_integer_fields = array_integer_fields.to_a
      raise CbetaError.new(500), "找不到匯入來源：#{path}" unless File.exist?(path)
    end

    def each
      return enum_for(:each) unless block_given?

      buffer = nil
      File.foreach(@path, encoding: 'UTF-8') do |line|
        buffer = +'' if line.include?('<sphinx:document')
        next if buffer.nil?

        buffer << line
        next unless line.include?('</sphinx:document>')

        yield parse_document(buffer)
        buffer = nil
      end
    end

    private

    def parse_document(xml)
      # Nokogiri 不接受未宣告的 sphinx namespace，去掉前綴後當一般 fragment 解析。
      fragment = Nokogiri::XML.fragment(xml.gsub('sphinx:', ''))
      node = fragment.at_css('document')
      raise CbetaError.new(500), '無法解析 xmlpipe2 document' if node.nil?

      doc = { '_id' => node['id'] }
      node.element_children.each do |child|
        doc[child.name] = normalize_value(child.name, child.text)
      end
      doc
    end

    def normalize_value(name, value)
      return value.to_i if @integer_fields.include?(name)
      return split_integers(value) if @array_integer_fields.include?(name)

      value
    end

    def split_integers(value)
      value.to_s.split(',').filter_map do |v|
        i = v.strip.to_i
        i unless i.zero?
      end
    end
  end
end
