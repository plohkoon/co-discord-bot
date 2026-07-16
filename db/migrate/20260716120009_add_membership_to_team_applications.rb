class AddMembershipToTeamApplications < ActiveRecord::Migration[8.1]
  def change
    # Nullable: applications are created with a membership going forward; any
    # pre-existing dev rows simply have no membership.
    add_reference :team_applications, :team_membership, foreign_key: true, null: true
    add_column :team_applications, :source, :integer, null: false, default: 0 # 0 applied, 1 manual
  end
end
