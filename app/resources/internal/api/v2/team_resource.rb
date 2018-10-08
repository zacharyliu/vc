class Internal::Api::V2::TeamResource < JSONAPI::Resource
  attribute :name
  attribute :full_name
  attribute :time_zone

  has_many :partners
end
