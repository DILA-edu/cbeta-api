desc "每季執行"
task :quarterly => :environment do |_t, _args|
  require_relative 'quarterly/quarterly'
  Quarterly.new.run
end

namespace :quarterly do
  desc "列出可單獨執行的每季步驟"
  task steps: :environment do
    require_relative 'quarterly/quarterly'
    puts Quarterly.step_names
  end

  # 例: rake 'quarterly:step[zip_html]' (step_ 前綴可省略)
  # 不等鍵盤輸入, 適合放在 tmux / nohup 裡跑。
  desc "非互動執行單一每季步驟"
  task :step, [ :name ] => :environment do |_t, args|
    abort "用法: rake 'quarterly:step[<步驟名稱>]', 步驟清單見 rake quarterly:steps" if args[:name].blank?

    require_relative 'quarterly/quarterly'
    Quarterly.new(interactive: false).run_one_step(args[:name])
  end
end
