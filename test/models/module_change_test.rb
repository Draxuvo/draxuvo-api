require "test_helper"

class ModuleChangeTest < ActiveSupport::TestCase
  def build(**attrs)
    ModuleChange.new({ company: companies(:pro_co), actor: users(:super_admin), module: "inventory", enabled: false }.merge(attrs))
  end

  test "a known module and a boolean state are valid; an unknown module is not" do
    assert build.valid?
    assert_not build(module: "spaceships").valid?
    assert_not build(enabled: nil).valid?
  end

  test "destroying a company removes its change log" do
    company = Company.create!(name: "Con registro")
    ModuleChange.create!(company: company, actor: users(:super_admin), module: "inventory", enabled: false)
    assert_difference -> { ModuleChange.count }, -1 do
      company.destroy!
    end
  end
end
