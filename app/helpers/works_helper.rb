module WorksHelper
  def get_work_info_by_id(n)
    if n.size > 6
      n.sub(/^(#{CBETA::CANON})\d{2,3}n(.*)$/, '\1\2')
    end
    Work.get_info_by_id(n)
  end
end
