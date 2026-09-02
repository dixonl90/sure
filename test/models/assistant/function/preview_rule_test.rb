require "test_helper"

class Assistant::Function::PreviewRuleTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @fn = Assistant::Function::PreviewRule.new(@user)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "preview_rule", definition[:name]
  end

  test "previews by existing rule id" do
    rule = @family.rules.create!(name: "Preview me", resource_type: "transaction", active: false)
    rule.conditions.create!(condition_type: "transaction_name", operator: "like", value: "ZZZ_NEVER_MATCHES%")

    result = @fn.call("id" => rule.id)

    assert result[:count].is_a?(Integer)
    assert_equal 0, result[:count]
    assert_equal [], result[:sample_transactions]
  end

  test "previews by inline conditions" do
    result = @fn.call(
      "conditions" => [
        { "condition_type" => "transaction_name", "operator" => "like", "value" => "ALSO_NEVER_MATCHES%" }
      ]
    )

    assert result[:count].is_a?(Integer)
    assert result[:rule_id].nil? # inline preview, not persisted
  end

  test "soft error when neither id nor conditions provided" do
    result = @fn.call
    assert_equal false, result[:success]
    assert_equal "conditions_required", result[:error]
  end

  test "soft error when rule id not found" do
    result = @fn.call("id" => SecureRandom.uuid)
    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
  end
end
