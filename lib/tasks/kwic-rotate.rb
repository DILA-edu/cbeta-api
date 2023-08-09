require 'fileutils'
require 'yaml'

class KwicRotate
  WORK    = Rails.configuration.x.kwic.temp
  PRODUCT = Rails.configuration.x.kwic.base

  def run
    Dir.mkdir(PRODUCT) unless Dir.exist?(PRODUCT)
    rotate('sa')
    rotate('sa-without-notes')
    rotate('text')
  end

  private

  def backup(folder)
    return unless Dir.exist? folder
    dest = folder + '-' + Time.new.strftime("%Y-%m-%d-%H%M%S")
    puts "Backup #{folder} => #{dest}"
    FileUtils.mv folder, dest
  end
  
  # 只有單卷 index, 沒有 info-tmp 了
  # def delete_info_tmp(folder)
  #   path = File.join(folder, 'info-tmp.dat')
  #   if File.exist?(path)
  #     puts "delete #{path}"
  #     File.unlink(path)
  #   end
    
  #   Dir.each_child(folder) do |f|
  #     path = File.join(folder, f)
  #     delete_info_tmp(path) if Dir.exist?(path)
  #   end
  # end

  def rotate(folder)
    src = File.join(PRODUCT, folder)
    if Rails.env.production?
      backup(src) 
    else
      FileUtils.remove_dir(src, true)
    end
        
    src = File.join(WORK, folder)
    dest = File.join(PRODUCT, folder)
    puts "move #{src} => #{dest}"
    FileUtils.mv src, dest    
  end
end