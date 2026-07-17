module Admin
  # Generic read-only browser over every model, driven by reflection — no
  # per-model code. Queries run without the tenant scope so admins see across
  # all guilds.
  class ResourcesController < BaseController
    # Columns never shown in the browser (secrets/tokens). None today; kept as
    # the seam so future sensitive columns get added here, not leaked.
    HIDDEN_COLUMNS = %w[].freeze

    # Columns shown in the list view (show renders all of them).
    LIST_LIMIT = 8

    def index
      @klass   = find_model!
      @columns = list_columns(@klass)

      ActsAsTenant.without_tenant do
        records, @meta = paginate(apply_search(@klass.order(id: :desc)))
        @records = records.to_a
      end
    end

    def show
      @klass   = find_model!
      @columns = visible_columns(@klass)

      ActsAsTenant.without_tenant do
        @record = @klass.find(params[:id])
        @associations = association_counts(@record)
      end
    end

    private

    def find_model!
      models.fetch(params[:model]) { raise ActiveRecord::RecordNotFound }
    end

    # Case-insensitive LIKE across the model's string/text columns (SQLite).
    def apply_search(scope)
      q = params[:q].to_s.strip
      return scope if q.blank?

      cols = visible_columns(@klass).select { |c| %i[string text].include?(c.type) }
      return scope if cols.empty?

      clauses = cols.map { |c| "LOWER(CAST(#{@klass.table_name}.#{c.name} AS TEXT)) LIKE :q" }
      scope.where(clauses.join(" OR "), q: "%#{q.downcase}%")
    end

    def association_counts(record)
      record.class.reflect_on_all_associations.filter_map do |assoc|
        next if assoc.macro == :belongs_to

        target_key = (models.key(assoc.klass) rescue nil)
        next unless target_key

        count = record.public_send(assoc.name).count rescue 0
        { name: assoc.name.to_s, model_key: target_key, count: count }
      end
    end

    def visible_columns(klass)
      klass.columns.reject { |c| HIDDEN_COLUMNS.include?(c.name) }
    end

    def list_columns(klass)
      priority = %w[id name status]
      visible_columns(klass)
        .sort_by { |c| priority.index(c.name) || 999 }
        .first(LIST_LIMIT)
    end
  end
end
