require "pr_releasenotes/configuration"

# Generate release notes from github pull requests, and optionally
# post to github releases
module PrReleasenotes

  def self.run
    ReleaseNotes.new.run
  end

  class ReleaseNotes

    require 'octokit'

    attr_reader :config, :git_client, :log

    def initialize

      @config = PrReleasenotes.configuration
      @log = config.log

      raise "No repo defined! Run with -h for usage." if config.repo.nil?
      raise "Missing github token! Run with -h for usage." if config.token.nil?

      Octokit.auto_paginate = config.auto_paginate
      @git_client ||= Octokit::Client.new(:access_token => config.token)
      log.info 'Created github client.'

    end

    def run
      # Infer start tag if necessary
      set_start_tag
      log.info "Retrieving release notes between #{config.start_tag} and #{config.end_tag.nil? ? 'now' : config.end_tag} on branch #{config.branch}"
      # First get a list of all tags on github
      get_all_tags
      # Get commits between start and end tags
      commits_for_tags = get_commits_for_tags
      # Get merged PRs for those commits
      prs = get_prs_for_commits(commits_for_tags)
      # Get release notes from those PRs
      notes_by_pr = get_releasenotes_for_prs(prs)
      # Convert to a single string
      notes_str = get_notes_str(notes_by_pr)
      # Optionally post to github as a new or updated release
      if config.github_release
        post_to_github(notes_str)
      else
        log.info "Release Notes:\n\n#{notes_str}"
      end
    end

    def get_all_tags
      @all_tags = git_client.tags(config.repo)
    end

    def set_start_tag
      if config.start_tag.nil?
        # If start tag isn't set, try to infer from the latest github release

        # First get the current tag or branch
        tag_or_branch = config.end_tag.nil? ? config.branch : config.end_tag
        begin
          releases = git_client.releases(config.repo)
                         .sort_by { |release| release[:created_at]}.reverse # order by create date, newest first
          release = releases.find { |release|
            unless release[:draft]
              # is a pre-release or published release, so check if this release is an ancestor of the end_tag
              # or the current branch

              # "diverged" indicates it was on a different branch & "behind" indicates it's after the
              # specified end_tag, so neither can be used as a start_tag
              # "ahead" indicates it's an ancestor and can be used as a start_tag
              git_client.compare(config.repo, release[:tag_name], tag_or_branch)[:status] == 'ahead'
            end
          }
          config.start_tag = release[:tag_name].sub /#{config.tag_prefix}/, ''
        rescue Octokit::Unauthorized => e
          throw e
        rescue StandardError
          log.error "No published releases found in #{config.repo} on or before #{tag_or_branch}. Either publish a release first, or specify a start tag or commit sha explicitly."
          exit 1
        end
      end
    end

    def get_date_for_tag(tags, tag_str)
      tagname = "#{config.tag_prefix}#{tag_str}"
      unless tags.empty?
        # From existing tags, find the tag for the specified tag_str and get its sha
        tag = tags.select {|tag| tag.name == tagname }.shift
        sha = tag[:commit][:sha] unless tag.nil?
      end

      unless sha
        # No tags exist, or specified tag_str wasn't found. Try treating the tag_str as a commit sha
        sha = tag_str
      end

      begin
        # get the commit for that sha, and the date for that commit.
        commit = git_client.commit( config.repo, sha )
      rescue Octokit::Error
        log.error "No commit found with tag name #{tagname} or sha #{tag_str}\n" and exit 1
      end
      commit[:commit][:author][:date]
    end

    def get_commits_for_tags

      # The github api does not directly support getting a list of commits since a tag was applied.
      # To work around this, we instead:

      # get the corresponding date for the tag corresponding to the start tag
      start_date = get_date_for_tag @all_tags, config.start_tag
      if config.end_tag.nil?
        # and get a list of commits since the start_date on the configured branch
        commits = git_client.commits_since config.repo, start_date, config.branch
        log.info "Got #{commits.length} commits on #{config.branch} between #{config.start_tag}(#{start_date}) and now"
      else
        # and the date for the end tag if not nil
        end_date = get_date_for_tag @all_tags, config.end_tag
        # and get a list of commits between the start/end dates on the configured branch
        commits = git_client.commits_between config.repo, start_date, end_date, config.branch
        log.info "Got #{commits.length} commits on #{config.branch} between #{config.start_tag}(#{start_date}) and #{config.end_tag}(#{end_date})"
      end
      log.debug "Commits: " + commits.map(&:sha).join(',')
      commits
    end

    def get_prs_for_commits(commits)
      # To optimize the number of calls to github, we'll combine commits into fewer search
      # calls, taking care not to exceed maximum query size of 256 chars

      # Searches need to restrict to merged pull requests in the specified repo
      search_suffix = " is:merged repo:#{config.repo}"
      # Max commits that can fit into a single query, including ',' join delimiter
      max_commits_per_search = 256/(config.min_sha_size + 1)

      shas = commits.map { |commit| commit[:sha][0..(config.min_sha_size-1)] }
      prs = shas.each_slice(max_commits_per_search).reduce([]) { |prs, sha_slice|
        # We slice the list of commits into sublists that'll fit into the github query size limits
        query = sha_slice.join(',') + search_suffix
        results = git_client.search_issues( query )
        log.info "Query '#{query}' matched #{results[:total_count]} PRs"
        # the reduce method allows us to accummulate PRs, skipping any
        prs.concat(results[:items])
      }
      # Dedupe prs
      prs.uniq! { |pr| pr[:number] }
      log.info "Retrieved #{prs.size} unique PRs"
      prs.each {|pr| log.debug pr[:title]}
      prs
    end

    def get_releasenotes_for_prs(prs)
      notes = prs.reduce([]) { |notes, pr|
        # Get release notes section
        unless pr[:body].nil?
          # Release notes exist for this PR, so do some cleanup
          body = pr[:body].strip.slice(config.relnotes_regex, config.relnotes_group)
          unless body.nil?
            body.gsub! /^<!--.+?(?=-->)-->/m, '' # strip off (multiline) comments
            body.gsub! /^\r?\n/, ''             # and empty lines
          end
        end
        # For PRs without release notes, add just the title
        notes << {:title => pr[:title], :date => pr[:closed_at], :prnum => pr[:number], :body => body}
      }
      notes.sort_by! {|note| note[:date]}.reverse! # order by PR merge date, newest first
    end

    def jiraize(notes_str)
      unless config.jira_baseurl.nil?
        # jira url is defined, so linkify any jira tickets in the notes
        # Regex: negative lookbehind(?<!...) for jira_prefix or beginning of link markdown,
        # followed by jira ticket pattern, followed by negative lookahead(?!...) for end of
        # link markdown
        #              |        neg lookbehind        |  | tkt pattern |  |neg lookahead |
        notes_str.gsub!(/(?<!#{config.jira_baseurl}|\[)\b([A-Z]{2,}-\d+)\b(?![^\[\]]*\]\()/, "[\\1](#{config.jira_baseurl}\\1)")
      end
      notes_str
    end

    def get_notes_str(notes_by_pr)
      notes_str = "Changes since #{config.tag_prefix}#{config.start_tag}:\r\n"
      if config.categorize
        # Categorize the notes, using the regex as the category names
        notes = notes_by_pr.reduce({}) { | notes, pr_note |
          if pr_note[:body].nil?
            # No explicit release notes
            if config.include_all_prs
              # Still want to include PR title under default category
              note = "* #{pr_note[:title]} ([##{pr_note[:prnum]}](https://github.com/#{config.repo}/pull/#{pr_note[:prnum]} \"Merged #{pr_note[:date]}\"))\r\n"
              # Initialize collapsible notes for category if it doesn't exist, and append note
              (notes[config.category_default] ||= "<details><summary>Show/Hide</summary><p>\r\n\r\n") << note
            end
          else
            # For each PR's notes, split by the category prefix
            # The lookahead (?=) regex allows including the category prefix delimiter at the beginning of each split record
            pr_note[:body].split(/(?=#{config.category_prefix})/).each { |pr_category_note|
              # Assume all of the line after the category_prefix is the category name. Slice off the category prefix and extract the category name
              category = pr_category_note.slice!(/#{config.category_prefix}[^\r]*/)
              # Remove trailing newlines
              pr_category_note.sub!(/^(\r\n)+|(\r\n)+$/, '')
              # Generate section header using PR title
              note = "* #{pr_note[:title]} ([##{pr_note[:prnum]}](https://github.com/#{config.repo}/pull/#{pr_note[:prnum]} \"Merged #{pr_note[:date]}\"))\r\n#{pr_category_note}\r\n"
              # Use default category if no category found
              category = category.nil? ? config.category_default : category.sub(/#{config.category_prefix}(.*)/,'\1')
              # Initialize notes for category if it doesn't exist, and append note
              (notes[category] ||= '') << note
            }
          end
          notes
        }
        notes[config.category_default] << "</p></details>" unless notes[config.category_default].nil?   # Close the collapsible section
        # Accumulate each category's notes
        notes_str << notes.sort.map { |category, note|
          note_str = category.nil? ? "#{config.relnotes_hdr_prefix}#{config.category_default}\r\n" : "#{config.relnotes_hdr_prefix}#{category}\r\n"
          note_str << note
        }.join("\r\n")
      else
        # No categorization required, use notes as is
        notes_str << notes_by_pr.reduce("") { | str, note |
          str << "#{config.relnotes_hdr_prefix}#{note[:title]} [##{note[:prnum]}](https://github.com/#{config.repo}/pull/#{note[:prnum]} \"Merged #{note[:date]}\")\r\n"
          str << "#{note[:body]}\r\n" unless note[:body].nil? || note[:body].empty?
          str
        }
      end
      jiraize notes_str
    end

    def post_to_github(notes_str)
      unless config.end_tag.nil?
        tag_name = "#{config.tag_prefix}#{config.end_tag}"
        if @all_tags.find { |tag| tag[:name] == tag_name }.nil?
          raise "#{tag_name} is not a valid end_tag. Releases can only be created or updated for existing end_tags."
        end
        begin
          release = git_client.release_for_tag(config.repo, tag_name)
          # Found existing release, so update it
          log.info "Found existing #{release.draft? ? 'draft ' : ''}#{release.prerelease? ? 'pre-' : ''}release with tag #{tag_name} at #{release.html_url}#{release.body.nil? || release.body.empty? ? '' : " with body: #{release.body}"}"
          begin
            release = git_client.update_release(release.url, { :name => tag_name, :body => notes_str, :draft => false, :prerelease => true })
            log.info "Updated pre-release #{release.id} at #{release.html_url} with body\n\n #{notes_str}"
          rescue Octokit::NotFound
            raise "Unable to post release to github. Ensure your token has the right permissions."
          end
        rescue Octokit::NotFound
          # no existing release, so try create a new one for this end_tag
          begin
            release = git_client.create_release(config.repo, tag_name, { :name => tag_name, :body => notes_str, :draft => false, :prerelease => true })
            log.info "Created pre-release #{release.id} at #{release.html_url} with body\n\n #{notes_str}"
          rescue Octokit::NotFound
            raise "Unable to post release to github. Ensure your token has the right permissions."
          end
        end
      end
    end

  end

end
