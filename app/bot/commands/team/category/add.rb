module Commands
  module Team
    module Category
      class Add < Commands::Base
        description "Add a roster category"
        string  :name, "Category name (directory section header, e.g. PvE Teams ⚔️)", required: true
        integer :position, "Sort order in the directory (lower first; default: last)"
        admin_only!

        def call
          category = TeamCategory.new(name: option(:name).to_s.strip, position: option(:position))
          if category.save
            respond("✅ Added category **#{category.name}**. Teams can pick it in `/team create|edit`.")
          else
            respond("⚠️ Couldn't add the category: #{category.errors.full_messages.to_sentence}")
          end
        end
      end
    end
  end
end
