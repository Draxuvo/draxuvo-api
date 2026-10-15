ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

Dir[File.expand_path("support/*.rb", __dir__)].sort.each { |file| require file unless file.end_with?("_test.rb") }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include StripeHelpers
    include CacheHelpers
    include EnvHelpers

    # Headers de una request autenticada: JWT del usuario y la empresa activa.
    def auth_headers(user, company = user.companies.first)
      token = JwtHelper.jwt_encode(user_id: user.id, email: user.email, full_name: user.full_name)
      headers = { "Authorization" => "Bearer #{token}" }
      headers["X-Company-Id"] = company.id.to_s if company
      headers
    end

    # Usuario con una membresía en `company` y el rol de esa empresa (el rol es por empresa).
    def create_member(company, role:, email: nil, user: nil)
      user ||= User.create!(first_name: "Miembro", last_name: role.to_s.camelize,
                            email: email || "#{role}-#{SecureRandom.hex(4)}@member.test",
                            phone: "5512340000", password: "password123", active: true)
      UserCompany.create!(user: user, company: company, role: role)
      user
    end
  end
end
