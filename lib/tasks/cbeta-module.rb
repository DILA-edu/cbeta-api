module CBETAModule
  def cb_xml_updated_at(path: nil)
    path = path || "#{@canon}/#{@vol}/#{@sutra_no}.xml"
    t = @git.log.path(path).first
    abort "取得 git log 發生錯誤, path: #{path}" if t.nil?
    t.date.strftime('%Y-%m-%d')
  end

  def elapsed_time(time_start)
    secs = (Time.now - time_start).round
    "花費時間: #{ChronicDuration.output(secs)}"
  end
end
