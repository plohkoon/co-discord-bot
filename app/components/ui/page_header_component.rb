module Ui
  class PageHeaderComponent < ApplicationComponent
    renders_one :actions

    def initialize(title:, back_href: nil, back_label: nil, subtitle: nil)
      @title = title
      @back_href = back_href
      @back_label = back_label
      @subtitle = subtitle
    end
  end
end
