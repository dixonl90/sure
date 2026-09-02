class Assistant::Function::DeleteRule < Assistant::Function
  class << self
    def name
      "delete_rule"
    end

    def description
      <<~INSTRUCTIONS
        Permanently deletes a rule by id. The rule's conditions, actions, and
        rule_run history are removed as well (cascading delete).

        This does not roll back any transaction modifications the rule made in
        the past; it only prevents future applications. Use update_rule with
        active=false if you want to deactivate without losing history.
      INSTRUCTIONS
    end
  end

  def params_schema
    build_schema(
      required: [ "id" ],
      properties: {
        id: {
          type: "string",
          description: "Rule ID from list_rules or get_rule."
        }
      }
    )
  end

  def call(params = {})
    id = params["id"].to_s
    return error("id_required", "Please provide a rule id.") if id.blank?

    rule = family.rules.find_by(id: id)
    return error("not_found", "Rule with id '#{id}' not found.") unless rule

    name = rule.name.presence || rule.id
    rule.destroy!

    {
      success: true,
      message: "Rule '#{name}' deleted.",
      deleted_id: id
    }
  end

  private
    def error(key, message)
      { success: false, error: key, message: message }
    end
end
