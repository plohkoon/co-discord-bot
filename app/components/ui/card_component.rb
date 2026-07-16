module Ui
  class CardComponent < ApplicationComponent
    def initialize(padding: "p-4", classes: nil)
      @padding = padding
      @classes = classes
    end

    def call
      tag.div(content, class: cx("rounded-xl border border-border bg-card", @padding, @classes))
    end
  end
end
