require "test_helper"

class Assistant::Function::ListRulesTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @fn = Assistant::Function::ListRules.new(@user)
    @existing = rules(:one)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "list_rules", definition[:name]
    assert_not_empty definition[:description]
  end

  test "returns rules with conditions and actions" do
    result = @fn.call

    assert result[:rules].is_a?(Array)
    assert result[:total_results] >= 1
    rule = result[:rules].find { |r| r[:id] == @existing.id }
    assert rule, "expected existing rule to be returned"
    assert rule[:conditions].is_a?(Array)
    assert rule[:actions].is_a?(Array)
  end

  test "active_only filters to active rules" do
    @existing.update!(active: false)
    result = @fn.call("active_only" => true)

    assert result[:rules].none? { |r| r[:id] == @existing.id }
  ensure
    @existing.update!(active: true)
  end
end
