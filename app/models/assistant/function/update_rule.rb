class Assistant::Function::UpdateRule < Assistant::Function
  class << self
    def name
      "update_rule"
    end

    def description
      <<~INSTRUCTIONS
        Updates an existing rule. Only fields that are provided are changed;
        omitted fields are left untouched.

        To replace the conditions or actions of a rule, pass the full new list
        under `conditions` or `actions`. Existing conditions and actions not
        in the new list are removed. If neither `conditions` nor `actions` is
        provided, the rule's existing conditions and actions are preserved.

        Conditions and actions accept the same shape as create_rule.

        Note: when the rule's `active` flag is set to true, the rule will run
        on its next scheduled execution; it is NOT executed synchronously by
        this call. Use preview_rule to see what transactions a rule would match
        before activating it.
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "id" ],
      properties: {
        id: {
          type: "string",
          description: "Rule ID from list_rules or get_rule."
        },
        name: {
          type: [ "string", "null" ],
          description: "New rule name. Use null to clear. Omit to leave unchanged."
        },
        active: {
          type: "boolean",
          description: "Set the active flag. Omit to leave unchanged."
        },
        effective_date: {
          type: [ "string", "null" ],
          description: "New effective date (YYYY-MM-DD). Use null to clear. Omit to leave unchanged."
        },
        conditions: {
          type: "array",
          description: "Full replacement list of condition hashes. Omit to leave existing conditions untouched.",
          items: { type: "object" }
        },
        actions: {
          type: "array",
          description: "Full replacement list of action hashes. Omit to leave existing actions untouched.",
          items: { type: "object" }
        }
      }
    )
  end

  def call(params = {})
    id = params["id"].to_s
    return error("id_required", "Please provide a rule id.") if id.blank?

    rule = family.rules.includes(:conditions, :actions).find_by(id: id)
    return error("not_found", "Rule with id '#{id}' not found.") unless rule

    Rule.transaction do
      apply_scalar_updates(rule, params)
      replace_conditions(rule, params["conditions"]) if params.key?("conditions")
      replace_actions(rule, params["actions"]) if params.key?("actions")
      rule.save!
    end

    rule.reload
    {
      success: true,
      rule: serialize_rule(rule),
      message: "Rule '#{rule.name.presence || rule.id}' updated."
    }
  rescue ActiveRecord::RecordInvalid => e
    error("validation_failed", e.record.errors.full_messages.join("; "))
  end

  private
    def apply_scalar_updates(rule, params)
      if params.key?("name")
        rule.name = params["name"].presence
      end
      if params.key?("active")
        rule.active = ActiveModel::Type::Boolean.new.cast(params["active"])
      end
      if params.key?("effective_date")
        rule.effective_date = parse_date(params["effective_date"])
      end
    end

    def parse_date(value)
      return nil if value.nil? || value.to_s.empty?
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def replace_conditions(rule, conditions_attrs)
      rule.conditions.destroy_all
      rule.conditions.reload
      Array(conditions_attrs).each do |attrs|
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

    def replace_actions(rule, actions_attrs)
      rule.actions.destroy_all
      rule.actions.reload
      Array(actions_attrs).each do |attrs|
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
