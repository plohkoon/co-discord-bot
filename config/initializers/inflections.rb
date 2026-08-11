# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

# Zeitwerk infers `Omniauth` from lib/omniauth, but the gem's module (and our
# strategy in lib/omniauth/strategies/battle_net.rb) spell it `OmniAuth`.
# Without this, production/CI eager loading aborts boot with
# "uninitialized constant Omniauth::Strategies::BattleNet".
Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect("omniauth" => "OmniAuth")
end
