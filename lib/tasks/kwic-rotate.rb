require 'fileutils'
require 'yaml'
class KwicRotate
  WORK    = Rails.configuration.x.kwic.temp
  PRODUCT = Rails.configuration.x.kwic.base

  def run
    Dir.mkdir(PRODUCT) unless Dir.exist?(PRODUCT)
    
    src = File.join(PRODUCT, 'sa')
    backup(src)
    
    delete_info_tmp(WORK)
    
    src = File.join(WORK, 'sa')
    dest = File.join(PRODUCT, 'sa')
    puts "move #{src} => #{dest}"
    FileUtils.mv src, dest
    
    src = File.join(PRODUCT, 'text')
    backup(src)
    
    src = File.join(WORK, 'text')
    dest = File.join(PRODUCT, 'text')
    puts "move #{src} => #{dest}"
    FileUtils.mv src, dest
  end

  def backup(folder)
    return unless Dir.exist? folder
    dest = folder + '-' + Time.new.strftime("%Y-%m-%d-%H%M%S")
    puts "Backup #{folder} => #{dest}"
    FileUtils.mv folder, dest
  end
  
  def delete_info_tmp(folder)
    path = File.join(folder, 'info-tmp.dat')
    if File.exist?(path)
      puts "delete #{path}"
      File.unlink(path)
    end
    
    Dir.each_child(folder) do |f|
      path = File.join(folder, f)
      delete_info_tmp(path) if Dir.exist?(path)
    end
  end
end