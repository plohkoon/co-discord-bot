module Ui
  class StatTileComponent < ApplicationComponent
    def initialize(value:, label:, accent: false)
      @value = value
      @label = label
      @accent = accent
    end

    def call
      tag.div(class: "rounded-xl border border-border bg-card px-4 py-3") do
        safe_join([
          tag.div(@value, class: cx("text-2xl font-semibold", @accent ? "text-gold" : "text-foreground")),
          tag.div(@label, class: "text-xs text-muted-foreground uppercase tracking-wide mt-0.5")
        ])
      end
    end
  end
end
