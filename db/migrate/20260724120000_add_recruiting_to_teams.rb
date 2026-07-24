class AddRecruitingToTeams < ActiveRecord::Migration[8.1]
  def change
    # Recruiting by default; a lead can close a team to applications, which hides
    # its roster Apply button and shows `closed_message` (or a default) instead.
    add_column :teams, :recruiting, :boolean, null: false, default: true
    add_column :teams, :closed_message, :text
  end
end
