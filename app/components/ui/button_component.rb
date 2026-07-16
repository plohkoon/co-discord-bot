module Ui
  # Renders a link (when `href:` is given) or a <button>. For form submit buttons
  # and button_to, use Ui::ButtonComponent.classes(...) to get the same styling.
  class ButtonComponent < ApplicationComponent
    BASE = "inline-flex items-center justify-center gap-2 rounded-md font-medium transition whitespace-nowrap cursor-pointer disabled:opacity-50".freeze
    VARIANTS = {
      gold:    "bg-gold text-black hover:brightness-110",
      outline: "border border-border bg-transparent text-foreground hover:bg-secondary/60",
      ghost:   "text-muted-foreground hover:text-foreground hover:bg-secondary/60",
      danger:  "text-light-red hover:bg-light-red/10"
    }.freeze
    SIZES = { md: "px-4 py-2 text-sm", sm: "px-3 py-1.5 text-xs" }.freeze

    def self.classes(variant: :gold, size: :md, extra: nil)
      [ BASE, VARIANTS.fetch(variant), SIZES.fetch(size), extra ].compact.join(" ")
    end

    def initialize(href: nil, variant: :gold, size: :md, **html)
      @href = href
      @variant = variant
      @size = size
      @html = html
    end

    def call
      css = self.class.classes(variant: @variant, size: @size, extra: @html.delete(:class))
      if @href
        link_to(@href, class: css, **@html) { content }
      else
        tag.button(content, class: css, **@html)
      end
    end
  end
end
