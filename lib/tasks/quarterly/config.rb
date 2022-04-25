module Config
  def get_config(env=nil)
    APP1 = 'cbapi1' # 用於：從上一季複製資料
    APP2 = 'cbapi3' # 有時候會跳過一季

    r = {
      v: 3, # 第幾季，用於 sphinx index 編號
      q1: '2022Q1', # 製作 change log 時比對 q1, q2
      q2: '2022Q3',
      publish: '2022-04' # 版權資訊 => 版本記錄 => 發行日期
    }

    r[:quarter] = r[:q2].sub(/^(\d+)(Q\d)$/, '\1.\2')
    r[:env] = env || Rails.env

    puts "mode: #{Rails.env}"
    case Rails.env
    when 'production'
      r[:git]           = '/home/ray/git-repos'
      r[:old]           = "/var/www/#{APP1}/shared"
      r[:old_data]      = File.join(r[:old],  'data')
      r[:root]          = "/var/www/#{APP2}/shared"
      r[:change_log]    = '/home/ray/cbeta-change-log'
      r[:ebook_convert] = '/usr/bin/ebook-convert'
    when 'development'
      r[:git]           = '/Users/ray/git-repos'
      r[:root]          = "/Users/ray/git-repos/cbeta-api"
      r[:change_log]    = '/Users/ray/Documents/Projects/CBETA/ChangeLog'
      r[:ebook_convert] = '/Applications/calibre.app/Contents/MacOS/ebook-convert'
    when 'cn'
      r[:git] = '/mnt/CBETAOnline/git-repos'
      r[:root] = "/mnt/CBETAOnline/cbdata/shared"
    end

    r[:data]     = File.join(r[:root], 'data')
    r[:public]   = File.join(r[:root], 'public')
    r[:juanline] = File.join(r[:data], 'juan-line')
    r[:figures]  = Rails.configuration.x.figures

    # eBook
    r[:download] = File.join(r[:public], 'download')
    r[:epub] = File.join(r[:download], 'epub')
    r[:mobi] = File.join(r[:download], 'mobi')
    r[:epub_template] = Rails.root.join('lib/tasks/quarterly/epub-template')

    # GitHub Repositories
    r[:authority]   = File.join(r[:git], 'Authority-Databases')
    #r[:cbr_figures] = File.join(r[:git], 'CBR2X-figures')
    r[:covers]      = File.join(r[:git], 'ebook-covers')
    r[:gaiji]       = File.join(r[:git], 'cbeta_gaiji')
    r[:metadata]    = File.join(r[:git], 'cbeta-metadata')
    r[:xml]         = File.join(r[:git], 'cbeta-xml-p5a')
    r
  end
end
