class HTMLNode
  attr_accessor :content, :attributes
  
  def initialize(tag)
    @tag = tag
    @attributes = {}
    @content = ''
  end

  def [] name
    @attributes[name]
  end
  
  def []= name, value
    set name.to_s, value.to_s
  end
  
  def copy_attributes(node)
    @attributes = node.attributes.dup
  end

  def end_tag
    "</#{@tag}>"
  end

  def open_tag
    r = "<#{@tag}"
    @attributes.each { |k,v| 
      r += %( #{k}="#{v}")
    }
    r + ">"
  end

  def key?(k)
    @attributes.key?(k)
  end

  def set(name, value)
    @attributes[name] = value
  end

  def to_s
    open_tag + @content + end_tag
  end
end
