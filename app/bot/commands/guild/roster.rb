module Commands
  module Guild
    # Post the public team directory: one seamless Components-V2 message with
    # category headers and an inline Apply button beside each team. Leads come
    # from the local team_officers mirror.
    #
    # Each channel holds at most one roster, optionally limited to some
    # categories (so retail teams can live in one channel and another set in
    # another); re-posting in a channel replaces the roster already there.
    class Roster < Commands::Base
      description "Post the team directory"
      channel :channel, "Channel to post in (default: here)", channel_types: [ :text ]
      string  :categories, "Comma-separated categories to include (default: all teams)", autocomplete: true
      admin_only!

      def call
        channel_id = (option(:channel) || event.channel&.id)&.to_i
        return respond("I can't find that channel.") unless channel_id&.positive?

        names = category_names(option(:categories))
        categories = names.map { |name| TeamCategory.named(name) }
        unknown = names.zip(categories).filter_map { |name, category| name unless category }
        if unknown.any?
          return respond("⚠️ This server has no categor#{unknown.one? ? 'y' : 'ies'} named " \
                         "#{unknown.map { |n| "**#{n}**" }.to_sentence} — pick from the autocomplete list.")
        end

        post = RosterPost.find_or_initialize_by(channel_id: channel_id)
        post.category_ids = categories.any? ? categories.map(&:id).uniq : nil

        teams = post.teams_from(current_guild.teams.active.includes(:team_category, :team_type, :team_officers).to_a)
        if teams.empty?
          return respond(categories.any? ? "No active teams in #{category_list(categories)} yet." :
                                           "No active teams to list yet — `/guild create` one first.")
        end

        scope = categories.any? ? " (#{category_list(categories)})" : ""
        respond("📋 Posting the team directory#{scope} in <##{channel_id}>…")

        replaced = post.message_ids
        post.message_ids = CoBot::RosterMessage.post(api: api, channel_id: channel_id, teams: teams)
        post.save!
        delete_messages(channel_id, replaced)
      rescue Discord::BotApi::Error
        follow_up("⚠️ I couldn't post in <##{channel_id}> — I need **Send Messages** there. " \
                  "Grant it to my role (or re-run the invite link) and try `/guild roster` again.")
      end

      # Completes the last comma-separated entry, keeping the ones before it.
      def autocomplete_categories(query)
        *chosen, partial = query.to_s.split(",", -1).map(&:strip)
        chosen = chosen.reject(&:blank?)
        prefix = chosen.map { |name| "#{name}, " }.join

        TeamCategory.ordered.where("name LIKE ?", "%#{partial}%").limit(25)
                    .reject { |c| chosen.any? { |name| name.casecmp?(c.name) } }
                    .map { |c| "#{prefix}#{c.name}" }
                    .select { |value| value.size <= 100 } # Discord's choice cap
                    .to_h { |value| [ value, value ] }
      end

      private

      def api = @api ||= Discord::BotApi.new

      def category_names(raw)
        raw.to_s.split(",").map(&:strip).reject(&:blank?).uniq(&:downcase)
      end

      def category_list(categories) = categories.map { |c| "**#{c.name}**" }.to_sentence

      # The roster this one replaces — best effort; a leftover message is
      # untidy, not harmful (its Apply buttons still work).
      def delete_messages(channel_id, message_ids)
        message_ids.each do |message_id|
          api.delete_message(channel_id, message_id)
        rescue Discord::BotApi::Error
          nil
        end
      end
    end
  end
end
