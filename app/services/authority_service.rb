class AuthorityService
  attr_reader :catalog, :persons

  def read_catalog
    @catalog = {}
    folder = Rails.configuration.x.work_info
    Dir["#{folder}/*.json"].each do |f|
      works = JSON.load_file(f)
      @catalog.merge!(works)
    end
  end

  def read_persons
    @persons = {}
    fn = File.join(
      Rails.configuration.x.authority, 
      'authority_person', 
      'Buddhist_Studies_Person_Authority.xml'
    )
    doc = File.open(fn) { |f| Nokogiri::XML(f) }
    doc.remove_namespaces!
    doc.xpath('//person').each do |person|
      id = person['id']
      @persons[id] = person_xml_to_h(person)
    end
  end

  private

  def person_xml_to_h(person)
    r = {}
    aliases = []
    person.xpath('persName').each do |name|
      s = name.content
      if not name.key?('type')
        r[:regular_name] = s if name['lang'] == 'zho-Hant'
      elsif name['type'] == 'alternative'
        aliases << s
      end
    end
    r[:aliases] = aliases unless aliases.empty?
    r
  end
end
