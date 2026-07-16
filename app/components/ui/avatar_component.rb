module Ui
  # A round letter avatar from a name/username.
  class AvatarComponent < ApplicationComponent
    SIZES = { sm: "w-8 h-8 text-xs", md: "w-10 h-10 text-sm", lg: "w-11 h-11 text-base" }.freeze

    def initialize(name:, size: :sm)
      @name = name
      @size = size
    end

    def call
      tag.div((@name.to_s.first(1).presence || "?").upcase,
        class: cx("rounded-full bg-secondary flex items-center justify-center text-muted-foreground font-semibold shrink-0",
                  SIZES.fetch(@size, SIZES[:sm])))
    end
  end
end
