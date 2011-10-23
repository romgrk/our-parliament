require 'test_helper'

class Scrapers::Mp::ExtractTest < ActiveSupport::TestCase
  def setup
    File.stubs(:directory?).returns(true)
    FileUtils.stubs(:mkdir_p)
  end

  def test_http_connection_with_correct_params
    Net::HTTP.expects(:start).with(Scrapers::Mp::Extract::HOST)
    Scrapers::Mp::Extract.new( anything ).run
  end

  def test_default_output_dir
    default_dir = File.join(Rails.root, "tmp", "data")
    assert_equal Scrapers::Mp::Extract.new(anything).output_dir, default_dir
  end

  def test_output_dir_override
    assert_equal Scrapers::Mp::Extract.new(anything, :output_dir => "foo").output_dir, "foo"
  end

  def test_output_dir_creation
    File.expects(:directory?).returns(false)
    FileUtils.expects(:mkdir_p).with("foo_dir")
    Scrapers::Mp::Extract.new(anything, :output_dir => "foo_dir")
  end

  def test_http_get_with_correct_url
    mock_http = mock
    mock_http.expects(:get).
              with("#{Scrapers::Mp::Extract::PATH}?#{Scrapers::Mp::Extract::QUERY_STRING}&Key=foo_id").
              returns(stub(:code => "200"))

    Net::HTTP.stubs(:start).yields(mock_http)
    File.stubs(:open)

    Scrapers::Mp::Extract.new( :foo_id ).run
  end

  def test_should_save_a_file_with_the_response_data
    stub_response = stub("HTTP Response", :code => "200", :body => :foo_response)
    stub_http = stub("http connection", :get => stub_response)
    Net::HTTP.stubs(:start).yields(stub_http)

    mock_file = mock
    mock_file.expects(:write).with(:foo_response)
    output_file = File.join(Rails.root, "tmp", "data", "mp_foo_id.html")
    File.expects(:open).with(output_file, "w").yields(mock_file)

    Scrapers::Mp::Extract.new( :foo_id ).run
  end

  def test_no_file_written_if_the_response_code_is_not_200
    mock_response = mock
    mock_response.expects(:code).returns("404")

    stub_http = stub("http connection", :get => mock_response)
    Net::HTTP.stubs(:start).yields(stub_http)
    File.expects(:open).never

    Scrapers::Mp::Extract.new( anything ).run
  end
end