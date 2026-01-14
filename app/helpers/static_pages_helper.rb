module StaticPagesHelper
  def link_to_url(url, label=nil)
    if label.nil?
      label = File.join(root_url, url)
    end

    url = File.join(root_url, url)
    "<a href='#{url}'>#{label}</a>".html_safe
  end

  def link_to_path(label, path, params={})
    if params.empty?
      url = path
    else
      url = "#{path}?#{params.to_query}"
    end

    if label.nil?
      label = File.join(root_url, url)
    end

    url = File.join(root_url, url)
    "<a href='#{url}'>#{label}</a>".html_safe
  end
end
