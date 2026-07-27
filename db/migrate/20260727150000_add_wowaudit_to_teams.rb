class AddWowauditToTeams < ActiveRecord::Migration[8.1]
  # wowaudit is keyed per *raid team*, not per account or per character, which
  # lines up with co-bot's Team — so the key lives here rather than in ENV.
  # Different teams in the same guild legitimately have different wowaudit
  # teams, and plenty of teams won't use it at all.
  #
  # Read-scoped roster data, but still a third-party credential: added to
  # Admin::ResourcesController::HIDDEN_COLUMNS so it never renders in the admin
  # browser.
  def change
    add_column :teams, :wowaudit_api_key, :string
    add_column :teams, :wowaudit_verified_at, :datetime
    add_column :teams, :wowaudit_team_name, :string
  end
end
