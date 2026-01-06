class ManticoreService
  def initialize
    @v = Rails.configuration.cb.v
  end

  def open
    @client = Mysql2::Client.new(
      host: '127.0.0.1',
      port: 9307,
      encoding: 'utf8mb4',
      connect_timeout: 3,
      read_timeout: 20,    # 可根據查詢複雜度調整, 寧可快速失敗（返回 503 / fallback），也不要讓 worker 卡 30 秒。
      write_timeout: 5
    )

    if @client.nil?
      msg = "開啟 MySQL connection 回傳 nil"
      logger.fatal msg
      raise CbetaError.new(500), msg
    end
    @client
  end

  def close
    return if @client.nil?
    @client.close
    @client = nil
  end
end
