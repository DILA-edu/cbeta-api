module SectionPrepare
  def run_section_prepare
    run_section "前置作業 (section-prepare.rb)" do
      if Rails.env.staging?
        step_copy_data_folder
        step_copy_public
        step_import_juanline
      end

      run_step 'update_from_github (update-github.rb)' do
        command "ruby update-github.rb #{@config[:git]}"
      end

      run_step 'check new canon (check-new-canon.rb)' do
        command "ruby check-new-canon.rb #{@config[:git]}"
      end

      step_create_juanline
      step_import_juanline  # import:layers 要用到，所以提早做
      step_copy_help
    end
  end

  def step_create_juanline
    run_step '產生 Juanline 資料 (juanline.rb)' do
      require_relative 'juanline'
      Juanline.new.produce
    end
  end

  def step_copy_data_folder
    return nil unless Dir.exist?(@config[:old_data])

    run_step '從上一季複製 data 資料夾' do
      src  = @config[:old_data]
      dest = @config[:data]
      confirm "請確認將由 #{src} 複製資料到 #{dest}"
      copy_folder(src, dest, ['download'])
    end

    run_step '從上一季複製 download 資料夾' do
      src  = File.join(@config[:old_data],  'download')
      dest = File.join(@config[:data],      'download')
      confirm "請確認將由 #{src} 複製資料到 #{dest}"
      copy_folder(src, dest, ['cbeta-text'])

      Dir.chdir(@config[:download]) do
        command "ln -sf text-for-asia-network cbeta-text"
      end
    end
  end

  def step_copy_help
    return unless @config.key?(:old)
    return nil unless Dir.exist?(@config[:old])

    run_step '從上一季複製檔案 Help HTML' do
      src = File.join(@config[:old], "public/help")
      dest = File.join(@config[:public], 'help')
      copy_folder(src, dest)
    end
  end

  def step_copy_public
    return nil unless Dir.exist?(@config[:old])

    run_step '從上一季複製 public 資料夾' do
      %w[help].each do |fn|
        src = File.join(@config[:old], "public", fn)
        dest = File.join(@config[:public], fn)

        copy_folder(src, dest)
      end
    end
  end

  def step_import_juanline
    run_step '匯入 各卷起始行 (rake import:juanline)' do
      system 'bundle exec rake import:juanline'
    end
  end
end
