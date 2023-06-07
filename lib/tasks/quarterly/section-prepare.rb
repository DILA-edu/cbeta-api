module SectionPrepare
  def run_section_prepare
    if Rails.env == 'staging'
      step_copy_data_folder
      step_copy_public
      step_import_juanline
    else
      run_step 'update_from_github (update-github.rb)' do
        system "ruby update-github.rb #{@config[:git]}"
      end

      run_step 'check new canon (check-new-canon.rb)' do
        system "ruby check-new-canon.rb #{@config[:git]}"
      end

      run_step '產生 Juanline 資料 (juanline.rb)' do
        require_relative 'juanline'
        Juanline.new.produce
      end

      # import:layers 要用到，所以提早做
      step_import_juanline

      step_copy_help
    end
  end

  def step_copy_data_folder
    return nil unless Dir.exist?(@config[:old_data])

    run_step '從上一季複製 data 資料夾' do
      puts "請確認將由 #{@config[:old_data]} 複製資料到 #{@config[:data]}"
      STDIN.getch
      copy_folder(@config[:old_data], @config[:data], ['figures'])
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
      %w[download help].each do |fn|
        src = File.join(@config[:old], "public", fn)
        dest = File.join(@config[:public], fn)

        if fn == 'download'
          exclude = ['cbeta-text']
        else
          exclude = []
        end
        
        copy_folder(src, dest, exclude)
      end
    end
  end

  def step_import_juanline
    run_step '匯入 各卷起始行 (rake import:juanline)' do
      system 'bundle exec rake import:juanline'
    end
  end
end
