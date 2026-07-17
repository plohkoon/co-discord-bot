module Admin
  # Gate + shared plumbing for the app-wide admin panel. Admin is the hardcoded
  # User::ADMIN_DISCORD_IDS list — there is no way to grant it through the app.
  class BaseController < ApplicationController
    PER_PAGE = 25

    before_action :require_admin

    private

    def require_admin
      return if current_user&.admin?

      redirect_to root_path, alert: "You don't have access to the admin area."
    end

    # Every model backed by a table, keyed by pluralized name ("teams" => Team).
    # Drives the generic resource browser and the dashboard model grid.
    def models
      @models ||= begin
        Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/models").to_s)
        ApplicationRecord.descendants
          .reject(&:abstract_class?)
          .select { |klass| klass.table_exists? rescue false }
          .sort_by(&:name)
          .index_by { |klass| klass.model_name.plural }
      end
    end
    helper_method :models

    # Minimal limit/offset pagination — returns [scoped relation, meta hash].
    def paginate(scope, per: PER_PAGE)
      count = scope.count
      pages = [ (count.to_f / per).ceil, 1 ].max
      page  = params[:page].to_i.clamp(1, pages)
      meta  = { page: page, pages: pages, count: count,
                prev: (page - 1 if page > 1), next: (page + 1 if page < pages) }
      [ scope.offset((page - 1) * per).limit(per), meta ]
    end
  end
end
