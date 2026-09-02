require "test_helper"

class Assistant::Function::UpdateRuleTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @fn = Assistant::Function::UpdateRule.new(@user)
    @category = @family.categories.first
    @rule = @family.rules.create!(
      name: "Original",
      resource_type: "transaction",
      active: true
    )
    @rule.conditions.create!(condition_type: "transaction_name", operator: "like", value: "ORIG%")
    @rule.actions.create!(action_type: "set_transaction_category", value: @category.id)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "update_rule", definition[:name]
    assert_includes definition[:params_schema][:required], "id"
  end

  test "updates name and active flag without touching conditions" do
    original_cond_count = @rule.conditions.count

    result = @fn.call("id" => @rule.id, "name" => "Renamed", "active" => false)

    assert result[:success]
    assert_equal "Renamed", result[:rule][:name]
    assert_equal false, result[:rule][:active]
    assert_equal original_cond_count, @rule.reload.conditions.count
  end

  test "replaces conditions when provided" do
    result = @fn.call(
      "id" => @rule.id,
      "conditions" => [
        { "condition_type" => "transaction_name", "operator" => "like", "value" => "NEW%" }
      ]
    )

    assert result[:success]
    assert_equal 1, @rule.reload.conditions.count
    assert_equal "NEW%", @rule.conditions.first.value
  end

  test "soft error when id missing" do
    result = @fn.call("name" => "x")
    assert_equal false, result[:success]
    assert_equal "id_required", result[:error]
  end

  test "soft error when rule not found" do
    result = @fn.call("id" => SecureRandom.uuid, "name" => "x")
    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
  end
end
