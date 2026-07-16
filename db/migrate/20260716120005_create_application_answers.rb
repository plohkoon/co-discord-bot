class CreateApplicationAnswers < ActiveRecord::Migration[8.1]
  def change
    create_table :application_answers do |t|
      t.references :team_application, null: false, foreign_key: true
      t.bigint  :guild_id, null: false
      t.integer :position, null: false, default: 0
      # Snapshot the question's key + label at submit time so an answer stays
      # readable even if the question is later reworded or deleted.
      t.string  :question_key, null: false
      t.string  :question_label, null: false
      t.text    :answer, null: false, default: ""

      t.timestamps
    end

    add_index :application_answers, [ :team_application_id, :position ]
    add_foreign_key :application_answers, :guilds, column: :guild_id, primary_key: :id
  end
end
