=begin
從 authority 經錄資料庫匯入作譯者資料
=end
require 'cbeta'
require 'json'
require 'pp'

class ImportJingluEditors
  def initialize
  end
  
  def import
    fn = Rails.root.join('data', 'catalog', 'jl_editors.csv')
  end  
  
  private

end