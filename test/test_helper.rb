# Load the Redmine helper
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

module PgpTestHelper

  def read_key(name)
    IO.read Rails.root.join("plugins", "openpgp", "test", name)
  end
end
