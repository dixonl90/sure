require "test_helper"

class Assistant::Function::GetRuleTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @fn = Assistant::Function::GetRule.new(@user)
    @existing = rules(:one)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "get_rule", definition[:name]
    assert_includes definition[:params_schema][:required], "id"
  end

  test "returns the rule with full detail" do
    result = @fn.call("id" => @existing.id)

    assert result[:rule][:id] == @existing.id
    assert result[:rule].key?(:conditions)
    assert result[:rule].key?(:actions)
    assert result[:rule].key?(:active)
  end

  test "soft error when id missing" do
    result = @fn.call
    assert_equal false, result[:success]
    assert_equal "id_required", result[:error]
  end

  test "soft error when rule not found" do
    result = @fn.call("id" => SecureRandom.uuid)
    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
  end
end
