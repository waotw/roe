require "test_helper"

# Lockout recovery: reset the admin password with a saved recovery code, no
# email/SSH needed. Focus here is the feedback a used vs. invalid code gives —
# a used code must say so specifically, not fall through to the generic miss.
class RecoveryCodeResetTest < ActionDispatch::IntegrationTest
  def setup
    @user  = users(:one)
    @email = @user.email_address
    @codes = @user.generate_recovery_codes! # plaintext "XXXX-XXXX-XXXX" strings
  end

  test "a valid unused code resets the password and consumes only that code" do
    post recovery_codes_path, params: {
      email_address: @email,
      recovery_code: @codes.first,
      password: "brand-new-password",
      password_confirmation: "brand-new-password"
    }

    assert_redirected_to new_session_path
    assert @user.reload.authenticate("brand-new-password"), "password should be updated"
    assert_equal 1, @user.recovery_codes.where.not(consumed_at: nil).count, "exactly one code consumed"
  end

  test "an already-used code is rejected with a specific 'already used' message" do
    used = @codes.first
    @user.find_recovery_code(used).consume!

    post recovery_codes_path, params: {
      email_address: @email,
      recovery_code: used,
      password: "attempt-password",
      password_confirmation: "attempt-password"
    }

    assert_redirected_to new_recovery_code_path(email_address: @email)
    assert_match(/already been used/i, flash[:alert])
    refute @user.reload.authenticate("attempt-password"), "a used code must not change the password"
  end

  test "an invalid code gives the generic message" do
    post recovery_codes_path, params: {
      email_address: @email,
      recovery_code: "ZZZZ-ZZZZ-ZZZZ",
      password: "x", password_confirmation: "x"
    }
    assert_match(/didn't match/i, flash[:alert])
  end

  test "a wrong email gives the generic message (no enumeration)" do
    post recovery_codes_path, params: {
      email_address: "nobody@example.com",
      recovery_code: @codes.first,
      password: "x", password_confirmation: "x"
    }
    assert_match(/didn't match/i, flash[:alert])
  end
end
