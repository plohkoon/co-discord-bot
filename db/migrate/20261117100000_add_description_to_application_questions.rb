class AddDescriptionToApplicationQuestions < ActiveRecord::Migration[8.1]
  # Discord caps a modal label at 45 chars but lets a description of up to 100
  # sit beneath it, so the full prompt has somewhere to go.
  def change
    add_column :application_questions, :description, :string
  end
end
