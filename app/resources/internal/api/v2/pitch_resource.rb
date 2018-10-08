class Internal::Api::V2::PitchResource < JSONAPI::Resource
  attribute :when
  attribute :decision
  attribute :deadline
  attribute :snapshot
  attribute :prevote_doc
  attribute :pitched, delegate: :pitched?
  attribute :past_deadline, delegate: :past_deadline?

  has_one :company
  has_many :votes
end
