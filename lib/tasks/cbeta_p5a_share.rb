require 'cbeta'

module CbetaP5aShare
  def each_canon(xml_root)
    Dir.entries(xml_root).sort.each do |c|
      next unless c.match(/^#{CBETA::CANON}$/)
      next if c == 'TX'
      yield(c)
    end
  end

  def ele_unclear(e)
    r = traverse(e)
    r = '▆' if r.empty?
    if block_given?
      r = yield r
    end
    r
  end

end