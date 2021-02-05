class TocNode < ActiveRecord::Base
  def label_path
    tokens = []
    t = self
    until t.nil?
      tokens.unshift t.label
      t = TocNode.find_by n: t.parent
    end
    tokens.join('/')
  end
end
