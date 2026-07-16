module Ui
  class EmptyStateComponent < ApplicationComponent
    def call
      tag.div(content, class: "rounded-xl border border-border bg-card/50 p-8 text-center text-sm text-muted-foreground")
    end
  end
end
