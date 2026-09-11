namespace :api_key do
  desc 'API key 控管的生效設定。Origin 白名單不進版控,上線前用這個確認'
  task config: :environment do
    allowlist = Rails.configuration.api_origin_allowlist
    required  = Rails.configuration.api_key_required

    puts "RAILS_ENV: #{Rails.env}"
    puts

    puts "api_key_required: #{required}"
    puts(if required
           '  → 過渡期已結束。未帶 key 且 Origin 未命中白名單的 request 會拿到 401。'
         else
           '  → 過渡期中。未帶 key 照樣放行（但帶了無效 key 一律 401）。'
         end)
    puts

    puts "api_origin_allowlist (來源: config/cb.yml，不進版控):"
    if allowlist.empty?
      puts '  (空)'
      puts '  ⚠️ 過渡期內沒事,但過渡期結束後,所有未帶 key 的網頁前端都會拿到 401。' if required == false
      puts '  ⚠️⚠️ 過渡期已結束且白名單為空 —— 網頁前端現在就是全部 401!' if required
    else
      allowlist.each { |origin| puts "  #{origin}" }
    end
    puts

    internal = Rails.configuration.api_internal_ip_ranges
    puts '校內 IP 範圍 (來源: config/cb.yml，不進版控，也不寫在對外說明頁):'
    if internal.empty?
      puts '  (空) → 校內與一般使用者一樣要受 60/min 限制'
    else
      internal.each { |range| puts "  #{range}/#{range.prefix}" }
      puts '  → 命中的 IP 免 key、且完全不套 rate limit'
    end
    puts

    puts "rate limit: 未帶 key #{ApiKeyAuthentication::ANONYMOUS_LIMIT}/min/IP、" \
         "帶 key #{ApiKeyAuthentication::KEYED_LIMIT}/min/user"
    puts "accounts DB: #{AccountsRecord.connection_db_config.database}"
    puts "有效 key 數: #{ApiKey.active.count}（使用者 #{User.count} 人）"
  end
end
