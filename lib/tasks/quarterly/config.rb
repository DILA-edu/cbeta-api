module Config
  CB  = Rails.configuration.cb
  Q1  = CB.r_prev  # 上一個季號
  Q2  = CB.r  # 目前季號，有時候會跳過一季
  PUB = CB.pub # 版權資訊 => 版本記錄 => 發行日期

  def get_config
    app1 = Q1.sub(/^.*(\d)$/, 'cbapi\1') # 用於：從上一季複製資料
    app2 = Q2.sub(/^.*(\d)$/, 'cbapi\1')

    r = {
      v:  Q2[-1].to_i, # 第幾季，用於 sphinx index 編號
      q1: Q1, # 製作 change log 時比對 q1, q2
      q2: Q2,
      publish: PUB
    }
    
    r[:quarter] = r[:q2].sub(/^(\d+)(Q\d)$/, '\1.\2')
    r[:git] = Rails.configuration.cb.git

    puts "mode: #{Rails.env}"
    case Rails.env
    when 'production', 'staging'
      r[:old]           = "/var/www/#{app1}/shared"
      r[:old_data]      = File.join(r[:old],  'data')
      r[:root]          = "/var/www/#{app2}/shared"
      r[:change_log]    = '/home/ray/cbeta-change-log'
      r[:ebook_convert] = '/usr/bin/ebook-convert'
    when 'development'
      r[:root]          = "/Users/ray/git-repos/cbeta-api"
      r[:change_log]    = '/Users/ray/Documents/Projects/cbeta/changelog'
      r[:ebook_convert] = '/Applications/calibre.app/Contents/MacOS/ebook-convert'
    when 'cn'
      r[:root] = "/mnt/CBETAOnline/cbdata/shared"
    end

    r[:data]     = File.join(r[:root], 'data')
    r[:public]   = File.join(r[:root], 'public')
    r[:juanline] = File.join(r[:data], 'juan-line')
    r[:figures]  = Rails.configuration.x.figures

    # eBook
    r[:download] = File.join(r[:data], 'download')
    r[:epub] = File.join(r[:download], 'epub')
    r[:mobi] = File.join(r[:download], 'mobi')
    r[:epub_template] = Rails.root.join('lib/tasks/quarterly/epub-template')

    # GitHub Repositories
    r[:authority]   = File.join(r[:git], 'Authority-Databases')
    r[:covers]      = File.join(r[:git], 'ebook-covers')
    r[:gaiji]       = File.join(r[:git], 'cbeta_gaiji')
    r[:metadata]    = File.join(r[:git], 'cbeta-metadata')
    r[:xml]         = File.join(r[:git], 'cbeta-xml-p5a')
    r
  end
end
