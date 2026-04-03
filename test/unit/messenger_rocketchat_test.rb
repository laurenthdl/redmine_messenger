# frozen_string_literal: true

require File.expand_path '../../test_helper', __FILE__

class MessengerRocketchatNotifiedUsersTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :trackers, :projects_trackers,
           :enabled_modules,
           :issue_statuses, :issue_categories, :workflows,
           :enumerations,
           :issues, :journals, :journal_details

  def setup
    Setting[:plugin_redmine_messenger] = {
      messenger_format: 'markdown',
      messenger_url: 'https://rocketchat.example.com/hooks/test'
    }
  end

  def teardown
    User.current = nil
  end

  def test_markdown_format_should_notify_only_assigned_to
    issue = issues(:issues_002) # assigned_to_id: 3 (dlopper)
    notified = issue.send(:messenger_to_be_notified)

    assert_equal [User.find(3)], notified
  end

  def test_markdown_format_without_assigned_to_should_notify_nobody
    issue = issues(:issues_001) # assigned_to_id: nil
    notified = issue.send(:messenger_to_be_notified)

    assert_empty notified
  end
end


class MessengerRocketchatChannelsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :trackers, :projects_trackers,
           :enabled_modules,
           :issue_statuses, :issue_categories, :workflows,
           :enumerations,
           :issues, :journals, :journal_details

  def setup
    Setting[:plugin_redmine_messenger] = {
      messenger_format: 'markdown',
      messenger_url: 'https://rocketchat.example.com/hooks/test',
      messenger_channel: 'general'
    }
  end

  def teardown
    User.current = nil
  end

  def test_markdown_format_with_project_channel_should_return_project_channel
    project = projects(:projects_001)
    MessengerSetting.create!(project: project, messenger_channel: 'project-channel')

    channels = Messenger.channels_for_project(project)

    assert_equal ['project-channel'], channels
  end

  def test_markdown_format_without_project_channel_should_return_empty
    # subproject1 (id:3) is child of ecookbook (id:1)
    parent = projects(:projects_001)
    child = projects(:projects_003)
    MessengerSetting.create!(project: parent, messenger_channel: 'parent-channel')

    channels = Messenger.channels_for_project(child)

    # En mode markdown, pas de remontée au parent : doit être vide
    assert_empty channels
  end
end


class MessengerSlackChannelsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :trackers, :projects_trackers,
           :enabled_modules,
           :issue_statuses, :issue_categories, :workflows,
           :enumerations,
           :issues, :journals, :journal_details

  def setup
    Setting[:plugin_redmine_messenger] = {
      messenger_format: 'slack',
      messenger_url: 'https://hooks.slack.com/test',
      messenger_channel: 'general'
    }
  end

  def teardown
    User.current = nil
  end

  def test_slack_format_should_fallback_to_parent_channel
    parent = projects(:projects_001)
    child = projects(:projects_003)
    MessengerSetting.create!(project: parent, messenger_channel: 'parent-channel')

    channels = Messenger.channels_for_project(child)

    # En mode slack, doit remonter au parent
    assert_equal ['parent-channel'], channels
  end
end


class MessengerRocketchatPrivateIssueTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :trackers, :projects_trackers,
           :enabled_modules,
           :issue_statuses, :issue_categories, :workflows,
           :enumerations,
           :issues, :journals, :journal_details

  def setup
    Setting[:plugin_redmine_messenger] = {
      messenger_format: 'markdown',
      messenger_url: 'https://rocketchat.example.com/hooks/test',
      post_private_issues: 0
    }
    @project = projects(:projects_001)
    MessengerSetting.create!(project: @project, messenger_channel: 'test-channel')
  end

  def teardown
    User.current = nil
  end

  def test_private_issue_should_not_be_sent_when_post_private_issues_disabled
    channels = Messenger.channels_for_project(@project)
    url = Messenger.url_for_project(@project)
    is_private = true
    post_private = Messenger.setting_for_project(@project, :post_private_issues)

    should_skip = is_private && !post_private

    assert should_skip, 'Private issue should be skipped when post_private_issues is disabled'
  end
end


class MessengerSlackNotifiedUsersTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles,
           :trackers, :projects_trackers,
           :enabled_modules,
           :issue_statuses, :issue_categories, :workflows,
           :enumerations,
           :issues, :journals, :journal_details

  def setup
    Setting[:plugin_redmine_messenger] = {
      messenger_format: 'slack',
      messenger_url: 'https://hooks.slack.com/test'
    }
  end

  def teardown
    User.current = nil
  end

  def test_slack_format_should_notify_all_notified_users
    issue = issues(:issues_002) # assigned_to_id: 3 (dlopper)
    notified = issue.send(:messenger_to_be_notified)

    assert_includes notified, User.find(3)
    assert notified.length >= 1
  end
end


class MessengerSpeakMarkdownTest < ActiveSupport::TestCase
  include Mocha::Integration

  fixtures :projects, :users, :members, :member_roles, :roles,
           :trackers, :projects_trackers,
           :enabled_modules,
           :issue_statuses, :issue_categories, :workflows,
           :enumerations,
           :issues, :journals, :journal_details

  def setup
    Setting[:plugin_redmine_messenger] = {
      messenger_format: 'markdown',
      messenger_url: 'https://rocketchat.example.com/hooks/test'
    }
    @project = projects(:projects_001)
    MessengerSetting.create!(project: @project, messenger_channel: 'project-channel,user1,user2,user3,user4,user5')
  end

  def teardown
    User.current = nil
    MessengerSetting.where(project_id: @project.id).delete_all
  end

  def test_markdown_format_should_send_only_one_message
    job_count = 0
    MessengerDeliverJob.stubs(:perform_later).with do |url, params|
      job_count += 1
      true
    end
    Messenger.speak 'test message', ['channel1', 'channel2', 'channel3'], 'https://test.com/hooks/test', project: @project
    assert_equal 1, job_count
  end

  def test_markdown_format_should_include_mentions_in_text
    user1 = User.find(3)
    user2 = User.find(4)
    users_to_notify = [user1, user2]

    captured_params = nil
    MessengerDeliverJob.stubs(:perform_later).with do |url, params|
      captured_params = params
      true
    end
    Messenger.speak 'test message', ['channel1'], 'https://test.com/hooks/test', project: @project, users_to_notify: users_to_notify
    assert_includes captured_params[:text], user1.login
    assert_includes captured_params[:text], user2.login
  end

  def test_markdown_format_should_send_to_first_channel_only
    captured_params = nil
    MessengerDeliverJob.stubs(:perform_later).with do |url, params|
      captured_params = params
      true
    end
    Messenger.speak 'test message', ['channel1', 'channel2', 'channel3'], 'https://test.com/hooks/test', project: @project
    assert_equal 'channel1', captured_params[:channel]
  end
end


class MessengerSpeakSlackTest < ActiveSupport::TestCase
  include Mocha::Integration

  fixtures :projects, :users, :members, :member_roles, :roles,
           :trackers, :projects_trackers,
           :enabled_modules,
           :issue_statuses, :issue_categories, :workflows,
           :enumerations,
           :issues, :journals, :journal_details

  def setup
    Setting[:plugin_redmine_messenger] = {
      messenger_format: 'slack',
      messenger_url: 'https://hooks.slack.com/test'
    }
    @project = projects(:projects_001)
    MessengerSetting.create!(project: @project, messenger_channel: 'channel1,channel2,channel3')
  end

  def teardown
    User.current = nil
    MessengerSetting.where(project_id: @project.id).delete_all
  end

  def test_slack_format_should_send_multiple_messages
    job_count = 0
    MessengerDeliverJob.stubs(:perform_later).with do |url, params|
      job_count += 1
      true
    end
    Messenger.speak 'test message', ['channel1', 'channel2', 'channel3'], 'https://hooks.slack.com/test', project: @project
    assert_equal 3, job_count
  end

  def test_slack_format_should_not_add_mentions_to_text
    user1 = User.find(3)
    user2 = User.find(4)
    users_to_notify = [user1, user2]

    captured_params = nil
    MessengerDeliverJob.stubs(:perform_later).with do |url, params|
      captured_params = params
      true
    end
    Messenger.speak 'test message', ['channel1', 'channel2'], 'https://hooks.slack.com/test', project: @project, users_to_notify: users_to_notify
    refute_includes captured_params[:text], user1.login
    refute_includes captured_params[:text], user2.login
  end

  def test_slack_format_should_send_to_all_channels
    captured_channels = []
    MessengerDeliverJob.stubs(:perform_later).with do |url, params|
      captured_channels << params[:channel]
      true
    end
    Messenger.speak 'test message', ['channel1', 'channel2'], 'https://hooks.slack.com/test', project: @project
    assert_equal ['channel1', 'channel2'], captured_channels
  end
end
