module FixtureHelper
  def fixture(path)
    File.read(File.expand_path("../fixtures/#{path}", __dir__))
  end
end
