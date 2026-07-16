# A colored pill for a membership or application status.
class StatusBadgeComponent < ApplicationComponent
  STYLES = {
    "pending"  => "bg-gold/15 text-gold",
    "active"   => "bg-emerald-500/15 text-emerald-300",
    "accepted" => "bg-emerald-500/15 text-emerald-300",
    "archived" => "bg-white/10 text-muted-foreground",
    "rejected" => "bg-light-red/15 text-light-red"
  }.freeze

  def initialize(status:)
    @status = status.to_s
  end

  def call
    tag.span(@status.capitalize,
      class: cx("inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium whitespace-nowrap",
                STYLES[@status] || "bg-secondary text-muted-foreground"))
  end
end
