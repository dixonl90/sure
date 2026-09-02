require "test_helper"

class Assistant::Function::DeleteRuleTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @fn = Assistant::Function::DeleteRule.new(@user)
    @rule = @family.rules.create!(name: "To delete", resource_type: "transaction", active: true)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "delete_rule", definition[:name]
    assert_includes definition[:params_schema][:required], "id"
  end

  test "deletes the rule" do
    id = @rule.id
    assert_difference -> { @family.rules.count }, -1 do
      result = @fn.call("id" => id)
      assert result[:success]
      assert_equal id, result[:deleted_id]
    end
  end

  test "soft error when rule not found" do
    result = @fn.call("id" => SecureRandom.uuid)
    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
  end

  test "soft error when id missing" do
    result = @fn.call
    assert_equal false, result[:success]
    assert_equal "id_required", result[:error]
  end
end
