namespace :user do
  desc '列出所有使用者'
  task list: :environment do
    if User.none?
      puts '(尚無使用者)'
      next
    end

    User.order(:created_at).each do |u|
      flag = u.admin? ? '[admin] ' : ''
      keys = u.api_keys.active.count
      puts "#{flag}#{u.provider}/#{u.uid} #{u.email} #{u.name} (有效 key: #{keys})"
    end
  end

  desc '開通 admin。用 email 指定,例: rake user:grant_admin[ray@dila.edu.tw]'
  task :grant_admin, [:email] => :environment do |_t, args|
    set_admin(args[:email], true)
  end

  desc '取消 admin。用 email 指定,例: rake user:revoke_admin[ray@dila.edu.tw]'
  task :revoke_admin, [:email] => :environment do |_t, args|
    set_admin(args[:email], false)
  end

  # email 在 users 表不是 unique(provider 端可能相同 email 不同 provider),
  # 因此符合的每一個帳號都一起設定。
  def set_admin(email, value)
    abort '請指定 email' if email.blank?

    users = User.where(email:)
    abort "查無 email 為 #{email} 的使用者" if users.none?

    users.each do |u|
      u.update!(admin: value)
      puts "#{u.provider}/#{u.uid} #{u.email} admin = #{value}"
    end
  end
end
