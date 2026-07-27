class AddAuthenticatedAtToUsers < ActiveRecord::Migration[8.1]
  # Until now a `users` row meant "someone who signed into the web app" —
  # `User.from_omniauth` was the only thing that created one. Everything on the
  # bot side identifies people by raw Discord snowflake instead, so the majority
  # of the people co-bot knows about have no row at all.
  #
  # That breaks down as soon as someone can own something. A character claimed
  # while applying in Discord needs an owner, and the applicant has almost
  # certainly never visited the website.
  #
  # So a `users` row now means "a person co-bot knows about", and this column
  # records whether they have ever actually authenticated. Null = a shadow
  # record created from a Discord interaction; they can hold characters and be
  # joined to memberships, but they have never proved they are anyone.
  #
  # Adoption is automatic: `from_omniauth` already does
  # find_or_initialize_by(discord_id:), so the first real sign-in fills in the
  # existing row rather than creating a second one.
  def change
    add_column :users, :authenticated_at, :datetime

    # Every row that exists today was created by the OAuth callback, so all of
    # them are genuinely authenticated.
    reversible do |dir|
      dir.up { execute "UPDATE users SET authenticated_at = created_at" }
    end
  end
end
