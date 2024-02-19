module SectionManticore
  def run_section_manticore
    run_section "Manticore" do
      step_manticore_create_folder
      step_manticore_config
      step_manticore_x2t
      step_manticore_t2x
      step_manticore_index
      step_manticore_vars
    end
  end

  def step_manticore_create_folder
    run_step 'manticore 建資料夾' do
      Dir.chdir(@data_dir) do
        @indexes.each do |s|
          command "sudo mkdir r#{@config[:v]}-#{s}"
        end
      end
    end
  end

  def step_manticore_config
    run_step 'manticore configuration' do
      command "bundle exec rake manticore:conf"
      puts "可以手動清除 #{base} 資料夾下的舊資料"
    end

    confirm "手動編輯 /etc/manticoresearch/manticore.conf"
  end

  def step_manticore_index    
    if Rails.env.development?
      run_step 'manticore index' do
        Dir.chdir('/Users/ray/Documents/Projects/CBETAOnline/manticore') do
          @indexes.each do |s|
            command "indexer --rotate #{s}"
          end
        end
      end
      return
    end

    run_step 'manticore index' do
      @indexes.each do |s|
        puts '-' * 10
        command "bundle exec rake manticore:build[#{s}]"
      end
    end

    run_step 'manticore restart' do
      command 'docker compose -f /home/ray/manticore/compose.yaml restart'

      puts '可手動清除舊版 Index: /var/lib/manticore'
      puts '注意 /var/lib/manticore/data 不能刪。'
    end
  end

  def step_manticore_t2x
    run_step '轉出 manticore 所需的 xml' do
      confirm <<~MSG
      需要部類、時間資訊，要執行過：
        rake import:category
        rake import:time
      MSG
      command 'rake manticore:t2x'
      command 'rake manticore:notes'
      command 'rake manticore:titles'
      command 'rake manticore:chunks'
    end
  end

  def step_manticore_vars
    run_step '匯入 異體字 (rake import:vars)' do
      puts '資料來源是 https://github.com/DILA-edu/cbeta-metadata/blob/master/variants/variants.json'
      confirm '這要在 Sphinx Index 建好之後才能執行'
      command 'rake import:vars'
    end
  end

  def step_manticore_x2t
    run_step '先把 XML P5a 轉為 text' do
      confirm '如果欄位有變更，要修改： /etc/manticoresearch/manticore.conf'
      command 'rake manticore:x2t'
    end
  end
end # end of module
