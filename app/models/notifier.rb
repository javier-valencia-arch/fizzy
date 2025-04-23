class Notifier
  attr_reader :source

  class << self
    def for(source)
      case source
      when ::Event
        Notifier::Event.new(source)
      when ::Mention
        Notifier::Mention.new(source)
      end
    end
  end

  def notify
    if should_notify?
      recipients.map do |recipient|
        Notification.create! user: recipient, source: source, creator: creator
      end
    end
  end

  private
    def initialize(source)
      @source = source
    end

    def should_notify?
      !creator.system?
    end
end
