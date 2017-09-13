class Http::Clearbit
  class Error < StandardError
  end

  def initialize(person)
    @person = person
  end

  def enhance
    @enhanced ||= Clearbit::Enrichment.find(email: @person.email,
                                            given_name: @person.first_name,
                                            family_name: @person.last_name,
                                            ip_address: @person.ip_address,
                                            stream: true)
  rescue Exception => e
    raise Error.new(e)
  end
end