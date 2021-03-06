ENV['APP_ENV'] = 'test'

require_relative 'app'
require 'test/unit'
require 'rack/test'
require 'mocha/test_unit'
require 'fakeredis'
require 'webmock/test_unit'

class BranchguardTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Branchguard
  end

  def setup
    Resque.inline = true
  end

  def test_it_rejects_unsigned_requests
    post '/payload', {'action': 'created'}
    assert last_response.unauthorized?
  end

  def test_it_rejects_improperly_signed_requests
    header 'X-Hub-Signature', '12345'
    post '/payload', {'action': 'created'}
    assert last_response.unauthorized?
  end

  def test_it_should_do_nothing_with_a_non_repository_event
    post_json '/payload', {'action': 'created'}, 'ping'
    assert_equal last_response.status, 202
  end

  def test_it_should_enqueue_a_job_for_a_repository_created_event
    data = {'action': 'created'}
    Resque.expects(:enqueue).returns(true).once
    post_json '/payload', data
    assert last_response.ok?
  end

  def test_it_should_protect_the_master_branch
    data = {
      'action': 'created',
      'repository': {
        'full_name': 'branchguard/test'
      }
    }
    Octokit::Client.any_instance.expects(:protect_branch).returns(true).once
    Octokit::Client.any_instance.stubs(:create_issue).returns({'number': '1'})
    Octokit::Client.any_instance.stubs(:close_issue).returns(true)
    post_json '/payload', data
  end

  def test_it_should_create_an_issue_to_notify_me_of_success
    data = {
      'action': 'created',
      'repository': {
        'full_name': 'branchguard/test'
      }
    }
    Octokit::Client.any_instance.stubs(:protect_branch).returns(true)
    Octokit::Client.any_instance.expects(:create_issue).returns({'number': '1'}).once
    Octokit::Client.any_instance.expects(:close_issue).returns(true).once
    post_json '/payload', data
  end

  def post_json(uri, data, x_github_event = 'repository')
    signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['SECRET_TOKEN'], data.to_json)
    header 'X-Hub-Signature', signature
    header 'X-GitHub-Event', x_github_event
    post uri, data.to_json
  end
end
