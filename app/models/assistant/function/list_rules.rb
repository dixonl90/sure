class Assistant::Function::ListRules < Assistant::Function
  class << self
    def default_page_size
      50
    end

    def name
      "list_rules"
    end

    def description
      <<~INSTRUCTIONS
        Returns rules defined for the user's family, sorted by most recently updated,
        with pagination.

        Use this when the user wants to see their existing rules, or before creating
        or updating a rule to check for duplicates and review current logic.

        Each rule entry includes its id, name, active flag, effective_date, and
        nested conditions and actions. Conditions describe when a rule applies
        (e.g. "transaction_name like TESCO%"). Actions describe what happens to
        matching resources (e.g. "set_transaction_category").

        Note on pagination:

        This function can be paginated. You can expect the following properties in the response:

        - `total_pages`: The total number of pages of results
        - `page`: The current page of results
        - `page_size`: The number of results per page (defaults to #{default_page_size})
        - `total_results`: The total number of results
      INSTRUCTIONS
    end
  end

  # Optional params are incompatible with strict function calling, which
  # requires every declared property to be listed in `required`.
  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [],
      properties: {
        page: {
          type: "integer",
          minimum: 1,
          description: "Page number (defaults to 1)"
        },
        page_size: {
          type: "integer",
          minimum: 1,
          maximum: MAX_PAGE_SIZE,
          description: "Results per page (defaults to #{self.class.default_page_size})"
        },
        active_only: {
          type: "boolean",
          description: "When true, only return active rules. Defaults to false (all rules)."
        }
      }
    )
  end

  def call(params = {})
    scope = family.rules.includes(:conditions, :actions).order(updated_at: :desc)
    scope = scope.where(active: true) if ActiveModel::Type::Boolean.new.cast(params["active_only"])

    page_size = resolved_page_size(params)
    pagy = Pagy.new(count: scope.count, page: resolved_page(params), limit: page_size)
    rules = scope.offset(pagy.offset).limit(pagy.limit)

    {
      rules: rules.map { |r| serialize_rule(r) },
      total_results: pagy.count,
      page: pagy.page,
      page_size: page_size,
      total_pages: pagy.pages
    }
  end

  private
    def serialize_rule(rule)
      {
        id: rule.id,
        name: rule.name,
        active: rule.active,
        effective_date: rule.effective_date&.iso8601,
        resource_type: rule.resource_type,
        created_at: rule.created_at&.iso8601,
        updated_at: rule.updated_at&.iso8601,
        conditions: rule.conditions.map { |c| serialize_condition(c) },
        actions: rule.actions.map { |a| serialize_action(a) }
      }
    end

    def serialize_condition(c)
      {
        id: c.id,
        condition_type: c.condition_type,
        operator: c.operator,
        value: c.value,
        parent_id: c.parent_id,
        sub_conditions: c.compound? ? c.sub_conditions.map { |sc| serialize_condition(sc) } : []
      }.compact
    end

    def serialize_action(a)
      {
        id: a.id,
        action_type: a.action_type,
        value: a.value
      }
    end
end
