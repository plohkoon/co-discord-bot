class AddOptionsToApplicationQuestions < ActiveRecord::Migration[8.1]
  # The choices for a multiple-choice or checkbox question, as a JSON array of
  # option labels. Unused (and kept empty) for the text and yes/no styles.
  def change
    add_column :application_questions, :options, :text
  end
end
