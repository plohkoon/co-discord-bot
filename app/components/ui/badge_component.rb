module Ui
  class BadgeComponent < ApplicationComponent
    VARIANTS = {
      muted: "bg-secondary text-muted-foreground",
      gold:  "bg-gold/15 text-gold",
      blue:  "bg-light-blue/15 text-light-blue"
    }.freeze

    def initialize(variant: :muted)
      @variant = variant
    end

    def call
      tag.span(content,
        class: cx("inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium whitespace-nowrap",
                  VARIANTS.fetch(@variant, VARIANTS[:muted])))
    end
  end
end
