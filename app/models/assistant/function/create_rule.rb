class Assistant::Function::CreateRule < Assistant::Function
  class << self
    def name
      "create_rule"
    end

    def description
      <<~INSTRUCTIONS
        Creates a new rule for the user's family.

        A rule has:
        - `name` (optional, free-text label)
        - `resource_type` (currently only "transaction" is supported)
        - `active` (boolean, default true)
        - `effective_date` (optional ISO date; null means applies to all history)
        - `conditions` (array; at least one required for non-compound rules)
        - `actions` (array; at least one required)

        Conditions:

        Each condition is a hash with:
        - `condition_type` (e.g. "transaction_name", "transaction_amount",
          "transaction_category", "transaction_merchant", "transaction_notes",
          "transaction_tag", "transaction_type", "transaction_account", or
          "compound")
        - `operator` ("=", "like", "or", or filter-specific; use "or" only for
          compound conditions)
        - `value` (string; for "compound" conditions, value should be "and" or
          "or" describing how sub-conditions combine)
        - `sub_conditions` (array of condition hashes, only when
          condition_type is "compound")

        Compound conditions are limited to one level of nesting. To express
        "A and (B or C)", create a compound("and") parent containing a leaf
        condition A and a compound("or") sub-parent containing B and C.

        Actions:

        Each action is a hash with:
        - `action_type` (e.g. "set_transaction_category", "set_transaction_tags",
          "set_transaction_merchant", "set_transaction_name", "auto_categorize",
          "auto_detect_merchants", "exclude_transaction", "set_as_transfer_or_payment",
          "set_investment_activity_label", "send_email_notification")
        - `value` (string; interpretation depends on action_type. For
          set_transaction_category this is a category id from get_categories.
          For set_transaction_tags, a comma-separated list of tag ids.)

        Note: each rule must have at least one action, and duplicate action
        types are not allowed on a single rule.
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "conditions", "actions" ],
      properties: {
        name: {
          type: "string",
          description: "Optional human-readable label for the rule."
        },
        resource_type: {
          type: "string",
          enum: [ "transaction" ],
          description: "Resource type. Only 'transaction' is currently supported."
        },
        active: {
          type: "boolean",
          description: "Whether the rule is active immediately. Defaults to true."
        },
        effective_date: {
          type: [ "string", "null" ],
          description: "Optional ISO 8601 date (YYYY-MM-DD). If set, the rule only applies to transactions on or after this date. Use null to clear."
        },
        conditions: {
          type: "array",
          description: "Array of condition hashes. At least one required for non-compound rules.",
          items: { type: "object" }
        },
        actions: {
          type: "array",
          description: "Array of action hashes. At least one required.",
          items: { type: "object" }
        }
      }
    )
  end

  def call(params = {})
    conditions_attrs = Array(params["conditions"])
    actions_attrs = Array(params["actions"])

    return error("conditions_required", "Provide at least one condition.") if conditions_attrs.empty?
    return error("actions_required", "Provide at least one action.") if actions_attrs.empty?

    rule = family.rules.new(rule_params(params))

    assign_conditions(rule, conditions_attrs)
    assign_actions(rule, actions_attrs)

    if rule.save
      # Reload to include generated ids on conditions/actions.
      rule.reload
      {
        success: true,
        rule: serialize_rule(rule),
        message: "Rule '#{rule.name.presence || rule.id}' created."
      }
    else
      error("validation_failed", rule.errors.full_messages.join("; "))
    end
  end

  private
    def rule_params(params)
      {
        name: params["name"].presence,
        resource_type: params["resource_type"].presence || "transaction",
        active: params.key?("active") ? ActiveModel::Type::Boolean.new.cast(params["active"]) : true,
        effective_date: parse_date(params["effective_date"])
      }.compact
    end

    def parse_date(value)
      return nil if value.nil? || value.to_s.empty?
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def assign_conditions(rule, conditions_attrs)
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

    def assign_actions(rule, actions_attrs)
      actions_attrs.each do |attrs|
        rule.actions.new(
          action_type: attrs["action_type"],
          value: attrs["value"]
        )
      end
    end

    def serialize_rule(rule)
      {
        id: rule.id,
        name: rule.name,
        active: rule.active,
        effective_date: rule.effective_date&.iso8601,
        resource_type: rule.resource_type,
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

    def error(key, message)
      { success: false, error: key, message: message }
    end
end
