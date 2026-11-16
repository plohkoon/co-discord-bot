# A pitch to start a new team, submitted from the "Apply to make a team"
# button beside a roster category header and posted to that category's admin
# channel by TeamProposalPostJob. Persisted first and posted second, so a
# Discord outage (or a deleted channel) never loses someone's pitch — admins
# can still read it in /admin.
class TeamProposal < ApplicationRecord
  include GuildScoped

  # The fixed questionnaire. Discord modals take at most five inputs, labels
  # are capped at 45 chars and descriptions at 100, hence the split: a short
  # `label`, with the full prompt as the description underneath it.
  #
  # Keys are the modal's input custom_ids. Past proposals stored their labels
  # alongside the answers, so rewording or regrouping these never rewrites
  # history.
  QUESTIONS = [
    { key: "name", label: "Team name & color",
      description: "What you'd like the team called, and the color for its role." },
    { key: "leadership", label: "Leadership",
      description: "Who's on your leadership team?" },
    { key: "content", label: "Game type, play style & content",
      description: "Content & level, days/times, your play style and the team environment you want." },
    { key: "on_board", label: "Who's on board?",
      description: "Anyone you've already gotten on board to join and build this team." },
    { key: "expectations", label: "Team expectations & recruitment plans",
      description: "Participation & commitment expected, who you hope to attract (casual, hardcore…), how you'll recruit" }
  ].freeze

  ANSWER_MAX = 1000

  belongs_to :team_category, optional: true

  serialize :answers, coder: JSON, type: Array

  validates :discord_user_id, presence: true
  validates :answers, presence: true

  def posted? = message_id.present?
end
