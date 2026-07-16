class ApplicationComponent < ViewComponent::Base
  private

  # Join class fragments, dropping nils/false.
  def cx(*classes)
    classes.flatten.select { |c| c.is_a?(String) && c.present? }.join(" ")
  end
end
