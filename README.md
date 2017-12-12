# pr_releasenotes

## Overview

Create release notes for your github repo using the descriptions of pull requests  in each release. Simply invoking:

    $ pr_releasenotes -r <user/repo> -t <token> -s <latest_tagged_release>

will generate release notes from your latest release tag to the tip of the master branch.

## Why this tool vs others

There are quite a few online tools for generating release notes based on github history, but all the ones I've found rely on commit messages. This makes them inflexible, since it would require rewriting commit history in order to make any changes to the generated notes.

This tool uses the pull request descriptions, so the release notes for any version can be updated at any time by simply updating the corresponding pull request's description and rerunning this tool.

Secondly, this tool provides the additional option to post the release notes back to the github releases page.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'pr_releasenotes'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install pr_releasenotes

## Usage

The minimum configuration necessary to run the tool is the repo, github token and a start release tag:

    $ pr_releasenotes --repo <user/repo> --token <token> --start <latest_tagged_release>

Additional options can be specified either by pasing a yaml configuration to the included executable:

    $ pr_releasenotes --config <config.yaml> --token <token> --start <start_version> --end <end_version> --branch <non-default branch>

or by invoking the gem directly from ruby code:

```ruby
require 'pr_releasenotes'

include PrReleasenotes

PrReleasenotes.configure do |config|
  config.repo('user/repo')
  config.token('github_token')
  config.parse_args(ARGV)
end

ReleaseNotes.new.run
```

Get a brief usage summary by running

    $ pr_releasenotes --help


See the [examples folder](examples) for some sample yaml configuration files.

### Github token use

This tool does require a github token, but you should create a token with only as many, or rather as few, permissions as you need.

A suitable token can be generated using the Github [Personal Access Tokens](https://github.com/settings/tokens) page. The token must have repo scope, but can be restricted to just public_repo scope if you only need to create release notes for public repositories.

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/bazaarvoice/pr_releasenotes.
