class AddReminderSettingsToTeams < ActiveRecord::Migration[8.0]
  def change
    # The team's daily review digest: whether to post it, how long an
    # application must have been waiting before it's worth mentioning, and
    # whether the digest pings the officer role. Defaults keep every existing
    # team on a pinging daily digest that skips same-day applications (they
    # already got the review message).
    add_column :teams, :review_digest, :boolean, default: true, null: false
    add_column :teams, :review_digest_after_days, :integer, default: 1, null: false
    add_column :teams, :remind_ping, :boolean, default: true, null: false

    # The sweep's durable bookkeeping: the guild-local date it last ran for this
    # team (so a retry can't post twice), and the digest message it last posted
    # (the marker for "the last one is still the newest thing in the channel").
    add_column :teams, :last_review_digest_on, :date
    add_column :teams, :last_review_digest_message_id, :bigint
  end
end
