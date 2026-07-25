class AddResponseTemplatesToTeams < ActiveRecord::Migration[8.1]
  def change
    change_table :teams do |t|
      # Per-team DM acknowledgements, nullable — blank falls back to a default
      # (Team::DEFAULT_APPLY_RESPONSE / DEFAULT_ABSENCE_RESPONSE). {team}/{user}
      # tokens are substituted at send time. apply fires on /apply today;
      # absence is inert plumbing for the future attendance feature.
      t.text :apply_response
      t.text :absence_response
    end
  end
end
