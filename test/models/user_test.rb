require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build_user(**attrs)
    User.new({ first_name: "Rosa", last_name: "Pérez", email: "rosa@example.test",
               phone: "5511112222", password: "Clave-Segura-9" }.merge(attrs))
  end

  test "a complete user is valid and defaults to staff, anaquel and system" do
    user = build_user
    assert user.valid?
    assert user.staff?
    assert_equal "anaquel", user.theme
    assert_equal "system", user.color_mode
  end

  test "requires first name, last name, email and phone" do
    user = User.new(password: "Clave-Segura-9")
    assert_not user.valid?
    %i[first_name last_name email phone].each { |attr| assert user.errors[attr].any?, "#{attr} debería ser obligatorio" }
  end

  test "name length is limited to 50 characters" do
    assert_not build_user(first_name: "a" * 51).valid?
    assert_not build_user(second_last_name: "a" * 51).valid?
    assert build_user(second_last_name: "").valid?
  end

  test "email is normalized to lowercase without spaces" do
    assert_equal "rosa@example.test", build_user(email: "  ROSA@Example.TEST ").email
  end

  test "email must be unique ignoring case and well formed" do
    assert_not build_user(email: users(:pro_staff).email.upcase).valid?
    assert_not build_user(email: "no-es-correo").valid?
  end

  test "password needs at least 8 characters, not only digits and not a common one (spec 052)" do
    assert_not build_user(password: "Ab1234").valid?
    assert_not build_user(password: nil).valid?
    assert_not build_user(password: "12345678").valid?
    assert_not build_user(password: "password123").valid?
    assert_not build_user(password: "QWERTY123").valid?
    assert build_user(password: "Clave-Segura-9").valid?
  end

  test "weak password messages are translated" do
    user = build_user(password: "12345678")
    user.valid?
    assert_equal [ I18n.t("auth.weak_password.only_digits") ], user.errors[:password]
    I18n.with_locale(:en) do
      user.valid?
      assert_no_match(/translation missing/i, user.errors.full_messages.join)
    end
  end

  test "an existing user can be updated without sending a password" do
    user = users(:pro_staff)
    assert user.update(phone: "5500000000")
    assert_not user.update(password: "123")
  end

  test "theme and color mode must be in the allowed lists" do
    assert_not build_user(theme: "neon").valid?
    assert_not build_user(color_mode: "sepia").valid?
    User::THEMES.each { |theme| assert build_user(theme: theme).valid? }
    User::COLOR_MODES.each { |mode| assert build_user(color_mode: mode).valid? }
  end

  test "authenticates with the right password only" do
    assert users(:pro_staff).authenticate("Clave-Segura-9")
    assert_not users(:pro_staff).authenticate("otra")
  end

  test "full_name joins the present name parts" do
    assert_equal "Rosa Pérez", build_user.full_name
    user = build_user(middle_name: "María", second_last_name: "Díaz")
    assert_equal "Rosa María Pérez Díaz", user.full_name
  end

  test "locked? is the opposite of active" do
    assert_not users(:pro_staff).locked?
    assert build_user(active: false).locked?
  end

  test "role_in returns the membership role, super_admin everywhere and nil without membership" do
    assert_equal "staff", users(:pro_staff).role_in(companies(:pro_co))
    assert_nil users(:pro_staff).role_in(companies(:one))
    assert_nil users(:pro_staff).role_in(nil)
    assert_equal "super_admin", users(:super_admin).role_in(companies(:one))
  end

  test "membership_for finds the membership of a company" do
    assert_equal user_companies(:pro_staff), users(:pro_staff).membership_for(companies(:pro_co))
    assert_nil users(:pro_staff).membership_for(nil)
  end

  test "compat_role uses the first membership, then the global role" do
    user = users(:pro_staff)
    create_member(companies(:basic_co), role: :owner, user: user)
    assert_equal "staff", user.compat_role
    assert_equal "super_admin", users(:super_admin).compat_role
    assert_equal "staff", build_user.tap(&:save!).compat_role
  end

  test "update_password validates the current password and the new one" do
    user = users(:pro_staff)
    assert_not user.update_password("mala", "nueva123", "nueva123")
    assert user.errors[:current_password].any?

    user = User.find(user.id)
    assert_not user.update_password("Clave-Segura-9", "", "")
    assert user.errors[:new_password].any?

    user = User.find(user.id)
    assert_not user.update_password("Clave-Segura-9", "123", "123")
    assert_not User.find(user.id).update_password("Clave-Segura-9", "nueva123", "otra123")

    user = User.find(user.id)
    assert user.update_password("Clave-Segura-9", "nueva123", "nueva123")
    assert user.reload.authenticate("nueva123")
  end

  test "reset_password_with_token validates the new password" do
    user = users(:pro_staff)
    assert_not user.reset_password_with_token("tok", "", "")
    assert_not User.find(user.id).reset_password_with_token("tok", "123", "123")
    other = User.find(user.id)
    assert_not other.reset_password_with_token("tok", "nueva123", "distinta")
    assert other.errors[:new_password_confirmation].any?
    done = User.find(user.id)
    assert done.reset_password_with_token("tok", "nueva123", "nueva123")
    assert done.reload.authenticate("nueva123")
  end

  test "scopes filter by email, role, text and system emails" do
    assert_includes User.by_email("staff@pro"), users(:pro_staff)
    assert_equal User.count, User.by_email("").count
    assert_includes User.by_role("super_admin"), users(:super_admin)
    assert_not_includes User.by_role("super_admin"), users(:pro_staff)
    assert_includes User.search("empleado"), users(:pro_staff)
    assert_includes User.by_text("staff@pro"), users(:pro_staff)
    assert_equal User.count, User.by_text(nil).count
    assert_equal User.all.to_a.sort_by(&:id), User.excluding_system_emails.to_a.sort_by(&:id)
    assert_equal User.order(created_at: :desc).to_a.map(&:id).sort, User.sorted.map(&:id).sort
  end

  test "managing keeps owners and admins even with an employee card, and drops staff-only users" do
    company = companies(:pro_co)
    owner = create_member(company, role: :owner)
    admin = create_member(company, role: :admin)
    company.employees.create!(name: "Admin con ficha", status: :active, user: admin)

    assert_includes User.managing, owner
    assert_includes User.managing, admin
    assert_not_includes User.managing, users(:pro_staff)
  end

  test "managing counts a role in any company, users without companies, and lists each user once" do
    mixed = create_member(companies(:pro_co), role: :staff)
    create_member(companies(:one), role: :owner, user: mixed)
    create_member(companies(:two), role: :admin, user: mixed)
    nobody = User.create!(first_name: "Sin", last_name: "Empresa", email: "sin-empresa@x.test", phone: "5512340000", password: "Clave-Segura-9", active: true)

    assert_includes User.managing, mixed
    assert_includes User.managing, nobody
    assert_equal 1, User.managing.where(id: mixed.id).count
  end


  # Spec 062: borrar a un usuario se lleva sus llaves de idempotencia y deja las de los demás.
  test "destroying a user deletes its idempotency keys only" do
    user = build_user(email: "con-llaves@example.test")
    user.save!
    other = users(:pro_staff)
    [ user, other ].each do |owner|
      IdempotencyKey.create!(user: owner, key: "k-#{owner.id}", request_method: "POST", request_path: "/api/v1/x",
                             response_status: 200, response_body: "{}")
    end

    user.destroy!

    assert_equal 0, IdempotencyKey.where(user_id: user.id).count
    assert_equal 1, IdempotencyKey.where(user_id: other.id).count
  end
end
