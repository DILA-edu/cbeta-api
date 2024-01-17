class ManticoreService
  def initialize
    @v = Rails.configuration.cb.v
  end

  def open
    @client = Mysql2::Client.new(:host => 0, :port => 9307, encoding: 'utf8mb4')
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
