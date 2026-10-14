ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Headers de una request autenticada: JWT del usuario y la empresa activa.
    def auth_headers(user, company = user.companies.first)
      token = JwtHelper.jwt_encode(user_id: user.id, email: user.email, full_name: user.full_name)
      headers = { "Authorization" => "Bearer #{token}" }
      headers["X-Company-Id"] = company.id.to_s if company
      headers
    end
  end
end
