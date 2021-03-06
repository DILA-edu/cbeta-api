require 'runbook'

module RunbookSectionSphinx
  def define_section_sphinx(config)
    step_sphinx_x2t = define_step_sphinx_x2t(config)
    step_sphinx_t2x = define_step_shpinx_t2x(config)
    step_sphinx_create_folder = define_step_sphinx_create_folder(config)
    step_sphinx_config = define_step_sphinx_config(config)
    step_sphinx_index = define_step_sphinx_index(config)
    step_sphinx_vars = define_step_sphinx_vars(config)

    Runbook.section "Sphinx" do
      if config[:env] == 'staging'
        add step_sphinx_create_folder
        add step_sphinx_config
      else
        add step_sphinx_x2t
        add step_sphinx_t2x
      end

      add step_sphinx_index
      add step_sphinx_vars
    end # Runbook.section
  end # def define_section_sphinx(config)

  def define_step_sphinx_config(config)
    Runbook.step 'sphinx configuration' do
      ruby_command do |rb_cmd, metadata, run|
        v = config[:v]

        fn = Rails.root.join('lib/tasks/quarterly/sphinx-template.conf')
        template = File.read(fn)
        s = template % { v: v }
        dest = "/etc/sphinxsearch/cbdata#{v}.conf"
        File.write(dest, s)
        new_confs = [dest]

        fn = Rails.root.join('lib/tasks/quarterly/sphinx-template-footnotes.conf')
        template = File.read(fn)
        s = template % { v: v }
        dest = "/etc/sphinxsearch/footnotes#{v}.conf"
        File.write(dest, s)
        new_confs << dest

        fn = Rails.root.join('lib/tasks/quarterly/sphinx-template-titles.conf')
        template = File.read(fn)
        s = template % { v: v }
        dest = "/etc/sphinxsearch/titles#{v}.conf"
        File.write(dest, s)
        new_confs << dest

        new_conf = ''
        new_confs.each do |s|
          new_conf += "cat #{s}\n"
        end

        fn = '/etc/sphinxsearch/sphinx.conf'
        s = File.read(fn)
        s.sub!(%r{cat /etc/sphinxsearch/base.conf}) do
          new_conf + $&
        end
        File.write(fn, s)
      end
      note '可以手動清除 /etc/sphinxsearch/sphinx.conf 的舊資料'
    end
  end

  def define_step_sphinx_create_folder(config)
    Runbook.step 'sphin 建資料夾' do
      ruby_command do |rb_cmd, metadata, run|
        v = config[:v]
        Dir.chdir('/var/lib/sphinxsearch') do
          ["", "-puncs", "-footnotes", "-titles"].each do |s|
            system "sudo mkdir data#{v}#{s}"
            system "sudo chown -R sphinxsearch:root data#{v}#{s}"
          end
        end
      end
    end
  end

  def define_step_sphinx_index(config)
    if config[:env] == 'staging'
      option = ''
    else
      option = ' --rotate'
    end

    if Rails.env.development?
      Runbook.step 'sphinx index' do
        ruby_command do |rb_cmd, metadata, run|
          Dir.chdir('/Users/ray/Documents/Projects/CBETAOnline/sphinx') do
            system "indexer --rotate cbeta"
            system "indexer --rotate footnotes"
            system "indexer --rotate titles"
          end
        end
      end
    else
      Runbook.step 'sphin index' do
        command "sudo indexer #{option} cbeta#{config[:v]}"
        command "sudo indexer #{option} footnotes#{config[:v]}"
        command "sudo indexer #{option} titles#{config[:v]}"
        command 'sudo service sphinxsearch restart'
        note '可手動清除舊版 Index: /var/lib/sphinxsearch'
        note '注意 /var/lib/sphinxsearch/data 不能刪。'
      end
    end
  end

  def define_step_shpinx_t2x(config)
    Runbook.step '轉出 sphinx 所需的 xml' do
      confirm <<~MSG
      需要部類、時間資訊，要執行過：
        rake import:category
        rake import:time
      MSG
      command 'rake sphinx:t2x'
      command 'rake sphinx:footnotes'
      command 'rake sphinx:titles'
    end
  end

  def define_step_sphinx_vars(config)
    Runbook.step '匯入 異體字 (rake import:vars)' do
      confirm '這要在 Sphinx Index 建好之後才能執行'
      note '資料來源是 https://github.com/DILA-edu/cbeta-metadata/blob/master/variants/variants.json'
      command 'rake import:vars'
    end
  end

  def define_step_sphinx_x2t(config)
    Runbook.step '先把 XML P5a 轉為 text' do
      confirm '如果欄位有變更，要修改： /etc/sphinxsearch/sphinx.conf'
      command 'rake sphinx:x2t'
    end
  end
end # end of module