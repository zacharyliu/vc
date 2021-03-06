class LoggedEvent < ActiveRecord::Base

  validates :reason, presence: true, uniqueness: { scope: [:record_id] }
  validates :count, presence: true

  def self.do_once(record, reason)
    return false if LoggedEvent.for(record, reason).present?
    LoggedEvent.log! reason, record, notify: 0
    yield
    true
  end

  def self.for(record, reason)
    where(record_id: record.id, reason: reason).first
  end

  def self.log!(reason, record, *args, notify: 1, to: nil, data: nil)
    Rails.logger.info "[LoggedEvent] #{reason} from #{record.class.name}(#{record.id})"
    log = where(record_id: record.id, reason: reason).first_or_initialize
    log.data[log.count] = data
    log.increment :count
    log.save!
    if log.count <= notify && to.present?
      Rails.logger.info "[LoggedEvent] Notifying #{to} of #{reason} (id: #{log.id})"
      emailer = "#{reason}_email"
      users = User.from_multi(to)
      ErrorMailer.email_and_slack! emailer, users, *args
    end
    log.count
  end
end
