class Assistant::Function::PreviewRule < Assistant::Function
  class << self
    def default_page_size
      25
    end

    def name
      "preview_rule"
    end

    def description
      <<~INSTRUCTIONS
        Returns the count and a sample of transactions that would match a rule
        WITHOUT applying any actions. This is the safest way to verify a rule
        before activating it or before adding destructive actions.

        Two ways to use this:

        1. By rule id (`id`): preview the matching transactions of an existing
           rule. If `id` refers to an inactive rule, the preview still works
           (active flag does not affect matching, only execution).

        2. By inline conditions (`conditions`, optional `effective_date`): preview
           an ad-hoc conditions tree without persisting a rule. Useful for
           checking "would this rule match what I want?" before committing.

        The response includes `count` (total matching transactions) and
        `sample_transactions` (a small paginated slice of id + name + amount +
        date, NOT the full transaction record). To inspect any individual
        transaction in detail, use get_transactions with the id.
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
        id: {
          type: "string",
          description: "Existing rule id to preview. Mutually exclusive with providing inline `conditions`."
        },
        conditions: {
          type: "array",
          description: "Inline conditions tree to preview. Use the same shape as create_rule's `conditions` parameter.",
          items: { type: "object" }
        },
        effective_date: {
          type: [ "string", "null" ],
          description: "Optional effective date for inline-condition previews. Ignored when `id` is provided."
        },
        page: {
          type: "integer",
          minimum: 1,
          description: "Page of sample transactions to return (defaults to 1)."
        },
        page_size: {
          type: "integer",
          minimum: 1,
          maximum: MAX_PAGE_SIZE,
          description: "Number of sample transactions to return per page (defaults to #{self.class.default_page_size}, max #{MAX_PAGE_SIZE})."
        }
      }
    )
  end

  def call(params = {})
    rule = nil
    if params["id"].present?
      rule = family.rules.find_by(id: params["id"].to_s)
      return error("not_found", "Rule with id '#{params["id"]}' not found.") unless rule
    else
      conditions_attrs = Array(params["conditions"])
      return error("conditions_required", "Provide either an `id` or inline `conditions`.") if conditions_attrs.empty?

      rule = family.rules.new(
        resource_type: "transaction",
        effective_date: parse_date(params["effective_date"])
      )
      build_conditions(rule, conditions_attrs)
    end

    scope = begin
      rule.send(:matching_resources_scope)
    rescue StandardError => e
      return error("preview_failed", "Could not evaluate rule conditions: #{e.class}: #{e.message}")
    end

    count = scope.count
    page_size = resolved_page_size(params)
    page = resolved_page(params)
    offset = (page - 1) * page_size
    sample = scope.order(date: :desc).offset(offset).limit(page_size)

    {
      count: count,
      sample_transactions: sample.map { |t| { id: t.id, name: t.name, amount: t.amount.to_f, date: t.date&.iso8601 } },
      page: page,
      page_size: page_size,
      total_pages: (count.to_f / page_size).ceil,
      rule_id: rule.persisted? ? rule.id : nil,
      effective_date: rule.effective_date&.iso8601
    }
  end

  private
    def parse_date(value)
      return nil if value.nil? || value.to_s.empty?
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def build_conditions(rule, conditions_attrs)
      conditions_attrs.each do |attrs|
        sub = Array(attrs["sub_conditions"])
        if attrs["condition_type"] == "compound"
          compound = rule.conditions.new(
            condition_type: "compound",
            operator: attrs["operator"].presence || (sub.any? ? "and" : "or"),
            value: attrs["value"].presence || (sub.any? ? "and" : "or")
          )
          sub.each { |sc| compound.sub_conditions.build(condition_attrs(sc)) }
        else
          rule.conditions.new(condition_attrs(attrs))
        end
      end
    end

    def condition_attrs(attrs)
      {
        condition_type: attrs["condition_type"],
        operator: attrs["operator"],
        value: attrs["value"]
      }
    end

    def error(key, message)
      { success: false, error: key, message: message }
    end
end
