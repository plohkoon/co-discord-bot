# Which WoW game a team plays. Retail and WoW: Forever are separate games with
# separate characters, so a character lookup has to know which one it's in.
# Every existing team is Retail — the only game co-bot spoke before this.
class AddGameToTeams < ActiveRecord::Migration[8.1]
  def change
    add_column :teams, :game, :string, default: "retail", null: false
  end
end
