ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  # fixtures :all  # fixture 없이 DB 직접 사용
end
