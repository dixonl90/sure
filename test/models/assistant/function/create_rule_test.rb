require "test_helper"

class Assistant::Function::CreateRuleTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @fn = Assistant::Function::CreateRule.new(@user)
    @category = @family.categories.first || @family.categories.create!(name: "Test Cat", color: "#000000", classification: "expense")
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "create_rule", definition[:name]
    assert_not_empty definition[:description]
    assert_includes definition[:params_schema][:required], "conditions"
    assert_includes definition[:params_schema][:required], "actions"
  end

  test "creates a rule with one condition and one action" do
    assert_difference -> { @family.rules.count } do
      result = @fn.call(
        "name" => "Tesco → Groceries",
        "conditions" => [
          { "condition_type" => "transaction_name", "operator" => "like", "value" => "TESCO%" }
        ],
        "actions" => [
          { "action_type" => "set_transaction_category", "value" => @category.id }
        ]
      )

      assert result[:success], result.inspect
      assert_equal "Tesco → Groceries", result[:rule][:name]
      assert_equal 1, result[:rule][:conditions].size
      assert_equal "transaction_name", result[:rule][:conditions].first[:condition_type]
      assert_equal 1, result[:rule][:actions].size
    end
  end

  test "defaults resource_type to transaction and active to true" do
    result = @fn.call(
      "conditions" => [ { "condition_type" => "transaction_name", "operator" => "like", "value" => "AMAZON%" } ],
      "actions" => [ { "action_type" => "set_transaction_category", "value" => @category.id } ]
    )

    assert result[:success]
    assert_equal "transaction", result[:rule][:resource_type]
    assert_equal true, result[:rule][:active]
  end

  test "supports compound conditions" do
    result = @fn.call(
      "name" => "Compound test",
      "conditions" => [
        {
          "condition_type" => "compound", "operator" => "and", "value" => "and",
          "sub_conditions" => [
            { "condition_type" => "transaction_name", "operator" => "like", "value" => "AMZN%" },
            { "condition_type" => "transaction_amount", "operator" => "<", "value" => "50" }
          ]
        }
      ],
      "actions" => [ { "action_type" => "set_transaction_category", "value" => @category.id } ]
    )

    assert result[:success], result.inspect
    compound = result[:rule][:conditions].first
    assert_equal "compound", compound[:condition_type]
    assert_equal 2, compound[:sub_conditions].size
  end

  test "soft error when conditions are missing" do
    result = @fn.call(
      "conditions" => [],
      "actions" => [ { "action_type" => "set_transaction_category", "value" => @category.id } ]
    )

    assert_equal false, result[:success]
    assert_equal "conditions_required", result[:error]
  end

  test "soft error when actions are missing" do
    result = @fn.call(
      "conditions" => [ { "condition_type" => "transaction_name", "operator" => "like", "value" => "X%" } ],
      "actions" => []
    )

    assert_equal false, result[:success]
    assert_equal "actions_required", result[:error]
  end

  test "scopes created rule to user's family" do
    @fn.call(
      "conditions" => [ { "condition_type" => "transaction_name", "operator" => "like", "value" => "X%" } ],
      "actions" => [ { "action_type" => "set_transaction_category", "value" => @category.id } ]
    )

    rule = @family.rules.last
    assert_equal @family.id, rule.family_id
  end
end
