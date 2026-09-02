class Assistant::Function::GetRule < Assistant::Function
  class << self
    def name
      "get_rule"
    end

    def description
      <<~INSTRUCTIONS
        Returns a single rule by id, including its full nested conditions tree
        and actions, plus metadata (created_at, updated_at, effective_date,
        active flag, resource_type).

        Use list_rules first to discover rule ids.

        The response also includes `affected_resource_count`, the number of
        transactions currently matching the rule's conditions (without applying
        any actions). This is useful for sanity-checking a rule before activating
        it or before adding a destructive action.
      INSTRUCTIONS
    end
  end

  def params_schema
    build_schema(
      required: [ "id" ],
      properties: {
        id: {
          type: "string",
          description: "Rule ID from list_rules"
        }
      }
    )
  end

  def call(params = {})
    id = params["id"].to_s
    return error("id_required", "Please provide a rule id.") if id.blank?

    rule = family.rules.includes(:conditions, :actions).find_by(id: id)
    return error("not_found", "Rule with id '#{id}' not found.") unless rule

    affected = safe_affected_count(rule)

    {
      rule: {
        id: rule.id,
        name: rule.name,
        active: rule.active,
        effective_date: rule.effective_date&.iso8601,
        resource_type: rule.resource_type,
        created_at: rule.created_at&.iso8601,
        updated_at: rule.updated_at&.iso8601,
        conditions: rule.conditions.map { |c| serialize_condition(c) },
        actions: rule.actions.map { |a| serialize_action(a) },
        affected_resource_count: affected
      }
    }
  end

  private
    def safe_affected_count(rule)
      rule.affected_resource_count
    rescue StandardError => e
      Rails.logger.warn("GetRule#safe_affected_count failed for rule #{rule.id}: #{e.class}: #{e.message}")
      nil
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
