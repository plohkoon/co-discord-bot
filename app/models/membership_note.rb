class MembershipNote < ApplicationRecord
  include GuildScoped

  belongs_to :team_membership

  validates :body, presence: true, length: { maximum: 2000 }

  def author_mention = "<@#{author_discord_id}>"
end
