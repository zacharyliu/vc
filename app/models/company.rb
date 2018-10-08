class Company < ActiveRecord::Base
  include Concerns::Cacheable
  include ActionView::Helpers::NumberHelper
  include Concerns::AttributeArrayable
  include Concerns::Domainable

  has_one :tweeter, as: :owner, dependent: :destroy
  has_many :pitches, -> { order(when: :desc ) }
  has_many :news, dependent: :destroy
  has_many :cards, -> { order(updated_at: :desc ).where(archived: false) }
  has_many :calendar_events
  has_many :investments, dependent: :destroy
  belongs_to :team
  has_and_belongs_to_many :users, -> { distinct }
  has_many :competitors, through: :investments
  has_and_belongs_to_many :founders, -> { distinct }

  validates :name, presence: true

  validates :domain, uniqueness: { allow_nil: true }
  validates :crunchbase_id, uniqueness: { allow_nil: true }
  validates :al_id, uniqueness: { allow_nil: true }
  validates :capital_raised, presence: true, numericality: { only_integer: true }

  array :industry

  STAGES = {
    applied: 0, # default
    pre_pitch: 1,
    pitch: 2,
    funding: 3,
    portfolio: 4,
    passed: 5,
    deferred: 6,
  }
  enum stage: STAGES

  scope :pitched, -> { joins(:pitches) }
  scope :decided, -> { pitched.where('pitches.decision IS NOT NULL') }
  scope :undecided, -> { pitched.where('pitches.decision IS NULL') }
  scope :portfolio, -> { pitched.where('pitches.funded': true) }

  after_create :add_to_wit!
  after_commit :start_relationships_job, on: :create
  before_validation :normalize_location

  def pitch
    @pitch ||= pitches.first
  end

  def card
    @card ||= cards.first
  end

  def in_list?(list)
    card.present? ? card.list.in?(Array.wrap(list)) : false
  end

  def passed?
    team.present? && in_list?([team.lists.rejected, team.lists.passed])
  end

  def funded?
    pitch&.funded? || (team.present? && in_list?(team.funded_lists))
  end

  def pitched?
    pitch.present? && pitch.pitched?
  end

  def partner_names
    cached { users.map(&:name) }
  end

  def capital_raised(format: false)
    format ? number_to_human(super(), locale: :money) : super()
  end

  def add_user(user)
    card.add_user user
    users << user
    save!
  end

  def add_comment!(comment, notify: false)
    return unless team.present?
    card.add_comment! comment
    team.notify!(comment, all: false) if notify
  end

  def as_json(options = {})
    super options.reverse_merge(only: [:id, :name, :description, :industry, :funded_at, :domain, :crunchbase_id, :location], methods: [:website, :complete?, :cb_url, :al_url])
  end

  def as_json_search(options = {})
    as_json options.reverse_merge(only: [:id, :name, :description, :industry, :domain], methods: [])
  end

  def as_json_api(options = {})
    options.reverse_merge!(
      methods: [:competitors],
      only: [
        :id,
        :name,
        :domain,
        :description,
      ]
    )
    key_cached(
      options.slice(:methods, :only, :except, :root, :include),
      expires_in: jitter(1, :day),
    ) do
      pitch_on = pitch.when.to_time.to_i if pitch.present?
      as_json(options).merge(
        team: team&.full_name,
        capital_raised: capital_raised(format: true),
        pitch_on: pitch_on,
        funded: funded?,
        passed: passed?,
        past_deadline: pitch&.past_deadline?,
        pitched: pitched?,
        partners: users.map { |user| { name: user.name, slack_id: user.slack_id }  },
        trello_url: card&.trello_url,
        stats: pitch&.stats,
        trello_id: card&.trello_id,
        snapshot_link: pitch&.snapshot,
      )
    end
  end

  def set_extra_attributes!
    pitch&.set_snapshot! if Rails.application.drfvote?
    set_crunchbase_attributes!
    set_angelist_attributes!
    set_competitors!
    set_capital_fields!
  end

  def invalidate_crunchbase_id!
    self.crunchbase_id = "#{Http::Crunchbase::Organization::INVALID_KEY}_#{param_name}"
    self.domain = nil
    self.description = nil
    self.capital_raised = funded? ? 20_000 : 0
    save!
  end

  def param_name
    name.gsub(' ', '').parameterize
  end

  def team
    return nil unless (cached_team = super).present?
    Team.send(cached_team.name)
  end

  def crunchbase_org(timeout = 3, raise_on_error: true)
    @crunchbase_org ||= Http::Crunchbase::Organization.new(self, timeout, raise_on_error)
  end

  def angelist_startup(timeout = 3)
    @angellist_startup ||= Http::AngelList::Startup.new(al_id, timeout: timeout)
  end

  def cb_slack_link
    cb_url.present? ? "<#{cb_url}|#{name}>" : name
  end

  def cb_url
    "https://www.crunchbase.com/organization/#{crunchbase_id}" if crunchbase_id.present?
  end

  def al_url
    "https://angel.co/startups/#{al_id}" if al_id.present?
  end

  def tweeter
    super || (Tweeter.where(username: twitter_username).first_or_create!(owner: self) if twitter_username.present?)
  end

  def competitions
    Competition.for_companies(self.id)
  end

  def competitions=(companies)
    companies.map do |company|
      Competition.from_companies!(self, company)
    end
  end

  def self.searchable_columns
    [:name]
  end

  def self.from_name(name)
    where(name: name).first_or_create!
  end

  def self.from_domain(domain)
    return nil unless domain.present?

    existing = Company.where(domain: domain).first
    return existing if existing.present?

    id = Http::Crunchbase::Organization.find_domain_id(domain, types: 'company')
    return nil unless id.present?
    Company.where(crunchbase_id: id).first_or_initialize.tap do |company|
      company.domain = domain
      company.send(:set_crunchbase_attributes!)
    end
  end

  def self.from_crunchbase_id(cb_id)
    return nil unless cb_id.present?

    existing = Company.where(crunchbase_id: cb_id).first
    return existing if existing.present?

    domain = Util.parse_domain(Http::Crunchbase::Organization.new(cb_id).homepage)
    from_domain domain
  end

  def complete?
    name.present? && description.present? && industry.present?
  end

  def humanized_industry
    return nil unless industry.present?
    industry.map { |i| Competitor::INDUSTRIES[i.to_sym] }.join(', ')
  end

  def latest_news
    @latest_news ||= news.order(created_at: :desc).limit(3)
  end

  def latest_tweets
    @latest_tweets ||= begin
      newsworthy = tweeter.newsworthy_tweets(3)
      newsworthy.present? ? newsworthy : tweeter.latest_tweets(3)
    end
  end

  def featured_competitors
    @featured_competitors ||= begin
      ids = investments
        .where(featured: true)
        .joins('INNER JOIN competitor_investor_aggs ON competitor_investor_aggs.competitor_id = investments.competitor_id')
        .order('SUM(COALESCE(competitor_investor_aggs.target_count, 0)) DESC')
        .limit(3)
        .group(:competitor_id)
        .pluck(:competitor_id)
      Competitor.where(id: ids)
    end
  end

  private

  def normalize_location
    self.location = Util.normalize_city(self.location) if self.location.present?
  end

  def start_relationships_job
    CompanyRelationshipsJob.perform_later(id)
  end

  def twitter_username
    cached { crunchbase_org(3, raise_on_error: false).twitter || angelist_startup.twitter }
  end

  def set_crunchbase_attributes!(timeout: 5)
    org = crunchbase_org(timeout)
    return unless org.found?
    self.name ||= org.name
    self.crunchbase_id = org.permalink
    self.domain = org.url
    self.description = org.description
    self.location = org.location
  end

  def set_angelist_attributes!(timeout: 5)
    startup = angelist_startup(timeout)
    return unless startup.found?
    self.al_id = startup.id
    self.domain ||= startup.url
    self.description ||= startup.description
    self.location ||= startup.locations.first
  end

  def set_competitors!
    self.competitors += Competitor.for_company(self)
  end

  def set_capital_fields!
    self.capital_raised = [crunchbase_org(5).total_funding.to_i || 0, funded? ? 20_000 : 0].max
    if crunchbase_org.acquisition.present?
      self.acquisition_date = Date.parse(crunchbase_org.acquisition.announced_on) rescue nil
    end
    if crunchbase_org.ipo.present?
      self.ipo_date = Date.parse(crunchbase_org.ipo.went_public_on) rescue nil
      self.ipo_valuation = crunchbase_org.ipo.opening_valuation
    end
  end

  def add_to_wit!
    return unless team.present?
    Http::Wit::Entity.new('company').add_value name
  end

  def add_graph_relationship!
    add_founder_graph_relationship!
    add_investor_graph_relationship!
  end

  def add_investor_graph_relationship!
    partners = investments.where.not(investor: nil)
    return unless partners.count > 1
    partners.each do |i1|
      partners.each do |i2|
        i1.investor.connect_to! i2.investor, :coinvest unless i1.id == i2.id
      end
    end
  end

  def add_founder_graph_relationship!
    return unless founders.count > 1
    founders.each do |f1|
      founders.each do |f2|
        f1.connect_to! f2, :cofound unless f1.id == f2.id
      end
    end
  end
end
