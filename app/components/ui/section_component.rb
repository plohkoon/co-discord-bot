module Ui
  # A titled section: an uppercase label + content.
  class SectionComponent < ApplicationComponent
    def initialize(title:, meta: nil, classes: nil)
      @title = title
      @meta = meta
      @classes = classes
    end
  end
end
