class Category < ApplicationRecord
  def self.get_n_by_name(name)
    c = Category.find_by name: name
    return nil if c.nil?
    c.n 
  end
end
