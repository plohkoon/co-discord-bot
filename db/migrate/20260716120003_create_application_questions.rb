class CreateApplicationQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :application_questions do |t|
      t.references :team, null: false, foreign_key: true
      t.bigint  :guild_id, null: false
      t.integer :position, null: false, default: 0
      t.string  :key, null: false          # stable machine key (survives rewording)
      t.string  :label, null: false        # Discord modal label (<= 45 chars)
      t.string  :placeholder               # <= 100 chars
      t.integer :style, null: false, default: 0  # enum: 0 short, 1 paragraph
      t.boolean :required, null: false, default: true
      t.integer :min_length
      t.integer :max_length

      t.timestamps
    end

    add_index :application_questions, [ :team_id, :position ]
    add_index :application_questions, [ :team_id, :key ], unique: true
    add_index :application_questions, :guild_id
    add_foreign_key :application_questions, :guilds, column: :guild_id, primary_key: :id
  end
end
