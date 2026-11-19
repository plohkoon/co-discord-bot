# Every application on a team in one table (a column per question), and the
# same table as CSV. Same audience as the membership page, which already shows
# these answers one person at a time: Manage Server or a lead of the team.
class TeamApplicationsController < ApplicationController
  include GuildScoping
  before_action :set_team
  before_action :require_team_access

  def index
    @report = Teams::ApplicationsReport.new(@team, status: params[:status])

    respond_to do |format|
      format.html
      format.csv do
        kind = [ @report.status, "applications" ].compact.join("-")
        send_data @report.to_csv, filename: Teams::CsvExport.filename(@team, kind), type: "text/csv"
      end
    end
  end

  private

  def set_team
    @team = @guild.teams.find(params[:team_id])
  end
end
