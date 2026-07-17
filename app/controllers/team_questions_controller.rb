class TeamQuestionsController < ApplicationController
  include GuildScoping
  before_action :set_team
  before_action :require_team_access

  def create
    question = @team.application_questions.build(question_params)
    question.key = generate_key(question.label)
    question.position = (@team.application_questions.maximum(:position) || -1) + 1

    if question.save
      redirect_to guild_team_path(@guild, @team), notice: "Question added."
    else
      redirect_to guild_team_path(@guild, @team), alert: question.errors.full_messages.to_sentence
    end
  end

  def update
    question = @team.application_questions.find(params[:id])
    if question.update(question_params)
      redirect_to guild_team_path(@guild, @team), notice: "Question saved."
    else
      redirect_to guild_team_path(@guild, @team), alert: question.errors.full_messages.to_sentence
    end
  end

  def destroy
    @team.application_questions.find(params[:id]).destroy
    redirect_to guild_team_path(@guild, @team), notice: "Question removed."
  end

  private

  def set_team
    @team = @guild.teams.find(params[:team_id])
  end

  # Note: :key is intentionally NOT user-editable — it's a stable machine key
  # generated from the label on create, so rewording a question keeps answers linked.
  def question_params
    params.require(:application_question)
          .permit(:label, :placeholder, :style, :required, :min_length, :max_length)
  end

  def generate_key(label)
    base = label.to_s.parameterize(separator: "_").presence || "question"
    key = base
    i = 2
    while @team.application_questions.exists?(key: key)
      key = "#{base}_#{i}"
      i += 1
    end
    key
  end
end
