module CbetaP5aShare
  def ele_unclear(e)
    r = traverse(e)
    r = '▆' if r.empty?
    if block_given?
      r = yield r
    end
    r
  end

end