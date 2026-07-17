module AdminHelper
  JOB_STATUS_STYLES = {
    "completed"   => "bg-emerald-500/15 text-emerald-300",
    "failed"      => "bg-light-red/15 text-light-red",
    "in_progress" => "bg-light-blue/15 text-light-blue",
    "scheduled"   => "bg-gold/15 text-gold",
    "ready"       => "bg-gold/15 text-gold",
    "blocked"     => "bg-white/10 text-muted-foreground",
    "pending"     => "bg-secondary text-muted-foreground"
  }.freeze

  def admin_job_status_badge(status)
    tag.span(status.humanize,
      class: "inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium whitespace-nowrap " \
             "#{JOB_STATUS_STYLES.fetch(status, JOB_STATUS_STYLES['pending'])}")
  end

  def admin_format_value(value)
    case value
    when nil                                     then tag.span("—", class: "text-muted-foreground/50")
    when true, false                             then value.to_s
    when Time, DateTime, ActiveSupport::TimeWithZone then admin_time(value)
    when Date                                    then value.iso8601
    when Array, Hash                             then value.to_json.truncate(120)
    else value.to_s.truncate(120)
    end
  end

  # Relative time with the exact instant in the tooltip.
  def admin_time(time)
    return tag.span("—", class: "text-muted-foreground/50") if time.blank?

    phrase = time.past? ? "#{time_ago_in_words(time)} ago" : "in #{distance_of_time_in_words(Time.current, time)}"
    tag.span(phrase, title: time.utc.iso8601)
  end

  def admin_record_label(record)
    %i[name display_name discord_username username label key].each do |attr|
      next unless record.respond_to?(attr)

      value = record.public_send(attr)
      return value if value.present?
    end
    "##{record.id}"
  end
end
