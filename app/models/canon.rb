class Canon < ActiveRecord::Base
  validates :id2, uniqueness: true
  validates :uuid, uniqueness: true
end
