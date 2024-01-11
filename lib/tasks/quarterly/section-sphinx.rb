module SectionSphinx
  def run_section_sphinx
    run_section "Sphinx" do
      step_sphinx_create_folder
      step_sphinx_config
      step_sphinx_x2t
      step_sphinx_t2x
      step_sphinx_index
      step_sphinx_vars
    end
  end

  def step_sphinx_config
    run_step 'sphinx configuration' do
      v = @config[:v]
      base = Rails.configuration.x.sphinx_base

      %w[text notes titles chunks].each do |index|
        fn = Rails.root.join("lib/tasks/quarterly/sphinx-template-#{index}.conf")
        template = File.read(fn)
        s = template % { v: v }
        dest = File.join(base, "#{v}-#{index}.conf")
        puts "write #{dest}"
        File.write(dest, s)
      end

      Dir.chdir(base) do
        command 'ruby merge.rb'
      end
      puts "可以手動清除 #{Rails.configuration.x.sphinx_base} 資料夾下的舊資料"
    end
  end

  def step_sphinx_create_folder
    run_step 'sphin 建資料夾' do
      Dir.chdir('/var/lib/sphinx') do
        @sphinx_folders.each do |s|
          command "sudo mkdir #{s}"
        end
      end
      change_sphinx_folder_owner
    end
  end

  def change_sphinx_folder_owner
    @sphinx_folders.each do |s|
      path = File.join("/var/lib/sphinx", s)
      system "sudo chown -R sphinx:sphinx #{path}"
    end
  end

  def step_sphinx_index
    indexes = %w[cbeta notes titles chunks]
    
    if Rails.env.development?
      run_step 'sphinx index' do
        Dir.chdir('/Users/ray/Documents/Projects/CBETAOnline/sphinx') do
          indexes.each do |s|
            command "indexer --rotate #{s}"
          end
        end
      end
      return
    end

    run_step 'sphin index' do
      indexes.each do |s|
        command "sudo indexer --config /etc/sphinx/sphinx.conf --rotate #{s}#{@config[:v]}"
      end

      # 不改權限會有問題 (不知道如何設定 indexer 新建檔案的預設 owner)
      change_sphinx_folder_owner
    end

    run_step 'sphin restart' do
      command 'sudo service sphinx restart'

      puts '可手動清除舊版 Index: /var/lib/sphinx'
      puts '注意 /var/lib/sphinx/data 不能刪。'
    end
  end

  def step_sphinx_t2x
    run_step '轉出 sphinx 所需的 xml' do
      confirm <<~MSG
      需要部類、時間資訊，要執行過：
        rake import:category
        rake import:time
      MSG
      command 'rake sphinx:t2x'
      command 'rake sphinx:notes'
      command 'rake sphinx:titles'
      command 'rake sphinx:chunks'
    end
  end

  def step_sphinx_vars
    run_step '匯入 異體字 (rake import:vars)' do
      puts '資料來源是 https://github.com/DILA-edu/cbeta-metadata/blob/master/variants/variants.json'
      confirm '這要在 Sphinx Index 建好之後才能執行'
      command 'rake import:vars'
    end
  end

  def step_sphinx_x2t
    run_step '先把 XML P5a 轉為 text' do
      confirm '如果欄位有變更，要修改： /etc/sphinxsearch/sphinx.conf'
      command 'rake sphinx:x2t'
    end
  end
end # end of module
