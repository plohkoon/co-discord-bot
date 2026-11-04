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
  QUESTIONS = [
    { key: "team", label: "Your team & the content it will pursue",
      description: "What would the team look like? Day/time, content level, etc." },
    { key: "style", label: "Play style, environment & who you want",
      description: "Preferred play style and team environment; the players you hope to attract (casual, hardcore…)" },
    { key: "commitment", label: "Participation & commitment",
      description: "Your expectations for participation and commitment." },
    { key: "on_board", label: "Who's already on board?",
      description: "Anyone you've already gotten on board to join and build this team." },
    { key: "recruitment", label: "Recruitment plans & leadership team",
      description: "How you plan to recruit, and who's on your leadership team." }
  ].freeze

  ANSWER_MAX = 1000

  belongs_to :team_category, optional: true

  serialize :answers, coder: JSON, type: Array

  validates :discord_user_id, presence: true
  validates :answers, presence: true

  def posted? = message_id.present?
end
