module Commands
  # Mixin for /team member <action> commands: declares the shared team + member
  # options (both autocompleted, member scoped to the typed team) and officer gating.
  module MemberCommand
    def self.included(base)
      base.string :team, "Team", required: true, autocomplete: true
      base.string :member, "Member", required: true, autocomplete: true
      base.officer_only!
    end

    private

    def resolve_membership
      team = resolve_team(option(:team))
      return (respond("Pick a team from the list.") && nil) unless team

      membership = team.team_memberships.find_by(id: option(:member))
      return (respond("Pick a member from the list.") && nil) unless membership

      membership
    end

    def autocomplete_team(query)
      current_guild.teams.active.matching(query).limit(25).to_h { |team| [ team.name, team.id.to_s ] }
    end

    def autocomplete_member(query)
      team = resolve_team(option(:team))
      return {} unless team

      member_scope(team).matching(query).order(updated_at: :desc).limit(25).to_h do |member|
        [ "#{member.discord_username.presence || member.discord_user_id} · #{member.status}", member.id.to_s ]
      end
    end

    # Which members this action applies to; override per command.
    def member_scope(team) = team.team_memberships

    def result_message(result, membership, verb:)
      case result.status
      when :already_decided then "#{membership.mention}'s application was already handled by someone else."
      when :error then "⚠️ #{result.error}"
      else "✅ #{membership.mention} #{verb}."
      end
    end
  end
end
