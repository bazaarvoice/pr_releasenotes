# pr_releasenotes

## Overview

Create release notes for your github repo using the descriptions of pull requests  in each release. Simply invoking:

    $ pr_releasenotes -r <user/repo> -t <token> -s <latest_tagged_release>

will generate release notes from your latest release tag to the tip of the master branch.

## Why this tool vs others

There are quite a few online tools for generating release notes based on github history, but all the ones I've found rely on commit messages. This makes them inflexible, since it would require rewriting commit history in order to make any changes to the generated notes. In addition, using commit messages forces irrelevant information such as `fixed typo`, `reverted incorrect commit`, and `updated tests/docs` into the release notes.

This tool uses pull request descriptions, so the release notes for any version can be updated at any time by simply updating the corresponding pull request's description and rerunning this tool. In addition, pull request descriptions can have a separate brief and focused section to expose only the necessary information into the release notes. 

Finally, this tool provides the additional option to post the release notes back to the github releases page.

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

The minimum configuration necessary to run the tool is the repo, github token and a starting tag or commit sha:

    $ pr_releasenotes --repo <user/repo> --token <token> --start <start_tag|sha>

Additional options can be specified either by passing a yaml configuration to the executable:

    $ pr_releasenotes --config <config.yaml> --token <token> --start <start_tag|sha> --end <end_tag|sha> --branch <non-default branch>

or by invoking the gem directly from ruby code:

```ruby
require 'pr_releasenotes'

PrReleasenotes.configure do |config|
  config.repo('user/repo')
  config.token('github_token')
  config.parse_args(ARGV)
end

PrReleasenotes.run
```

Get a brief usage summary by running

    $ pr_releasenotes --help


See the [examples folder](examples) for some sample yaml configuration files.

### Running as part of a release build

This tool can be invoked right after a release build to automatically add release notes to a newly created release.

#### Regular releases

For regular releases where a previous release already exists, and a new release is being created, this tool can be invoked after the release is built by using the following form:

    $ pr_releasenotes --repo <user/repo> --token <token> --end <current_release_tag>
    
The tool will set the start_tag to the latest tagged release prior to the current one and generate release notes from that release to the current one.

#### Initial release

For the initial release from a repo, there is no previous release, so the tool must be run with an explicit start sha or tag:

    $ pr_releasenotes --repo <user/repo> --token <token> --start <commit_sha> --end <current_release_tag>
 
Both the `--start` and `--end` parameters support sha values as well as tags, so release notes can be generated between any two tags or commits.


### Github token permissions

This tool does require a github token since it accesses the github api. However any token created should have only as many, or rather as few, permissions as needed.

A suitable token can be generated using the Github [Personal Access Tokens](https://github.com/settings/tokens) page. Depending on the use, the following permissions are required on the token:

* Print out the release notes for a public repo on stdout:
  * no permissions selected, i.e. public access
* Update releases on github for a public repo:
  * public_repo scope, i.e. write access to the user's public repos.
* Print release notes or update releases on private repos:
  * repo scope, i.e. read/write access to all private repos.

**Add permissions with caution, and only if necessary!**

Unfortunately, github currently does not provide separate write access for releases from write access for code, so these permissions are required for the corresponding use. Although this gem was written to make the minimal necessary use of the token, both the public_repo and repo scope tokens are nearly as powerful as your password, and should be well protected.

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/bazaarvoice/pr_releasenotes.
