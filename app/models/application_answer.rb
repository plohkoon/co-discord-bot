class ApplicationAnswer < ApplicationRecord
  include GuildScoped

  belongs_to :team_application
end
