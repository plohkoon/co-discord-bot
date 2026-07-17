class AddEmoteToTeams < ActiveRecord::Migration[8.1]
  def change
    # Optional emoji (unicode or <:custom:id>) shown before the team name in
    # the roster directory heading.
    add_column :teams, :emote, :string
  end
end
