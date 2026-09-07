namespace :origin do
  desc '過渡期埋點: 各 Origin 的 request 數。例: rake origin:report[30]'
  task :report, [:days] => :environment do |_t, args|
    days = (args[:days] || 30).to_i
    since = Date.current - (days - 1)

    rows = OriginStat.where(used_on: since..Date.current)
                     .group(:origin).sum(:count)
                     .sort_by { |_origin, count| -count }

    if rows.empty?
      puts "#{since} ~ #{Date.current} 沒有資料"
      next
    end

    total = rows.sum { |_origin, count| count }
    puts "#{since} ~ #{Date.current}（共 #{days} 天），total #{total}"
    puts
    puts format('%-45s %12s %7s  %s', 'Origin', 'count', '%', '白名單')
    puts '-' * 78

    rows.each do |origin, count|
      pct = (count * 100.0 / total).round(1)
      hit = OriginStat.new(origin:).allowlisted? ? '命中' : ''
      puts format('%-45s %12s %6.1f%%  %s', origin, count, pct, hit)
    end

    puts
    none = rows.to_h[OriginStat::NONE].to_i
    puts "Origin 為 nil 的比例: #{(none * 100.0 / total).round(1)}%"
    puts '（過渡期結束後，這部分若沒帶 key 就會拿到 401 —— ' \
         '要先確認裡面沒有 cbetaonline 前端的流量）'
  end
end
