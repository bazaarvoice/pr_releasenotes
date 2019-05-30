module PrReleasenotes

  class << self
    attr_accessor :config
  end

  def self.configuration
    self.config ||= Configuration.new
  end

  def self.configure
    configuration
    yield(config)
  end

  class Configuration

    require 'optparse'
    require 'yaml'
    require 'logger'
    require 'to_regexp'
    require "pr_releasenotes/version"

    attr_accessor :repo, :token, :tag_prefix, :min_sha_size, :start_tag, :end_tag,
                  :branch, :include_all_prs, :github_release, :relnotes_group,
                  :categorize, :category_prefix, :category_default, :relnotes_hdr_prefix,
                  :jira_baseurl, :auto_paginate, :log

    attr_reader :relnotes_regex


    def initialize
      @log = Logger.new(STDOUT)
      @log.level = Logger::INFO

      # Name of your repo in user/repo format
      @repo = nil
      # If all your tags have a common prefix, add that here, and use just the varying suffix as the argument
      @tag_prefix = ''
      # Short sha uniqueness threshold. Shas shorter than this may collide with other commits
      @min_sha_size = 7
      # Tag range from which release notes should be gathered
      @start_tag = nil  # nil for latest released tag
      @end_tag = nil    # nil for latest commit. nil will skip the creation of a github release
      # Release notes will be pulled from PRs merged to this branch
      @branch = 'master'
      # Whether to include even PRs without explicit release notes
      @include_all_prs = true
      # Finish by posting release notes to github
      @github_release = false

      # Release notes parsing options. Note that comments will always get stripped
      # By default, only the PR titles will be used, so match nothing from the description
      @relnotes_regex = /.\A/
      @relnotes_group = 0 # group to capture from the regex

      # Set categorization options
      @categorize = false # false to disable categorization
      @category_prefix = '^\* '
      # PRs without categories will get included into this default category
      @category_default = '<!--99-->Other'
      # Add a prefix to the release notes items
      @relnotes_hdr_prefix = '* '

      # Optional jira url to auto link all strings matching a jira ticket pattern
      # Set to nil to skip auto link
      @jira_baseurl = nil

      # !!!CAUTION!!! this will auto paginate, and potentially overrun your rate limits! Do not try to get
      # release notes for all history for your project. Limit to no more than 2-3 pages worth of commits per
      # the UI.
      @auto_paginate = false
    end

    def dump
      instance_variables.map do |var|
        "#{var}: #{instance_variable_get(var)}"
      end
    end

    def relnotes_regex= (regex_str)
      @relnotes_regex = regex_str.to_regexp
    end

    def parse_args (args)
      opt_parser = OptionParser.new do |opts|
        opts.banner = "Usage: pr_releasenotes [options]"

        opts.separator ''
        opts.on('-c', '--config <config.yaml>', 'Yaml configuration') do |config|
          begin
            YAML.load_file(config).each do |k, v|
              begin
                # Try calling public setter for this option
                public_send("#{k}=",  v)
              rescue NoMethodError => e
                raise "#{e.message} caused by (#{config}) Invalid key '#{k}'"
              end
            end
          rescue StandardError => e
            raise "Unable to parse #{config} caused by #{e.message}"
          end
        end

        opts.separator ''
        opts.on('-r', '--repo   <user/repo>', 'Repo to scan for pull requests') do |repo|
          @repo = repo
        end
        opts.on('-t', '--token  <token>', 'Github token with repo scope') do |token|
          @token = token
        end

        opts.separator ''
        opts.on('-s', '--start  <tag|sha>', 'Get release notes starting from this tag or sha. (Default: latest release)') do |tag|
          @start_tag = tag
        end
        opts.on('-e', '--end    <tag|sha>', 'Get release notes till this tag or sha. (Default: latest commit, skips creating github release)') do |tag|
          @end_tag = tag
        end
        opts.on('-b', '--branch <branchname>', 'Use pull requests to this branch. (Default: master)') do |branch|
          @branch = branch
        end

        opts.separator ''
        opts.on('-p', '--post-to-github', 'Create/update release on github') do
          @github_release = true
        end

        opts.separator ''
        opts.on('-d', '--debug', 'Enable debug logging') do
          @log.level = Logger::DEBUG
          @log.debug 'Debug mode enabled'
        end
        opts.on_tail('-h', '--help', 'Prints this help') do
          puts opts
          exit
        end
        opts.on_tail('-v', '--version', 'Show version') do
          puts ::VERSION
          exit
        end
      end

      opt_parser.parse!(args)
      if @github_release && @end_tag.nil?
        log.error "Cannot post to github without an end tag. Specify an end_tag or skip posting to github."
        exit 1
      end
    end

  end
end
