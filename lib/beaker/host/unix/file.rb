module Unix::File
  include Beaker::CommandFactory

  def tmpfile(name)
    execute("mktemp -t #{name}.XXXXXX")
  end

  def tmpdir(name)
    execute("mktemp -dt #{name}.XXXXXX")
  end

  def system_temp_path
    '/tmp'
  end

  # Handles any changes needed in a path for SCP
  #
  # @note This is really only needed in Windows at this point. Refer to
  #   {Windows::File#scp_path} for more info
  def scp_path path
    path
  end

  def path_split(paths)
    paths.split(':')
  end

  def file_exist?(path)
    result = exec(Beaker::Command.new("test -e #{path}"), :acceptable_exit_codes => [0, 1])
    result.exit_code == 0
  end

  # Gets the config dir location for package information
  #
  # @raise [ArgumentError] For an unknown platform
  #
  # @return [String] Path to package config dir
  def package_config_dir
    case self['platform']
    when /fedora|el-|centos/
      '/etc/yum.repos.d/'
    when /debian|ubuntu|cumulus/
      '/etc/apt/sources.list.d'
    else
      msg = "package config dir unknown for platform '#{self['platform']}'"
      raise ArgumentError, msg
    end
  end

  # Returns the repo filename for a given package & version for a platform
  #
  # @param [String] package_name Name of the package
  # @param [String] build_version Version string of the package
  #
  # @raise [ArgumentError] For an unknown platform
  #
  # @return [String] Filename of the repo
  def repo_filename(package_name, build_version)
    variant, version, arch, codename = self['platform'].to_array
    variant = 'el' if variant == 'centos'

    repo_filename = "pl-%s-%s-" % [ package_name, build_version ]
    case variant
    when /fedora|el|centos/
      fedora_prefix = ((variant == 'fedora') ? 'f' : '')
      pattern = "%s-%s%s-%s.repo"
      pattern = "repos-pe-#{pattern}" if self.is_pe?

      repo_filename << pattern % [
        variant,
        fedora_prefix,
        version,
        arch
      ]
    when /debian|ubuntu|cumulus/
      repo_filename << "%s.list" % [ codename ]
    else
      msg = "#repo_filename: repo filename pattern not known for platform '#{self['platform']}'"
      raise ArgumentError, msg
    end

    repo_filename
  end

  # Gets the repo type for the given platform
  #
  # @raise [ArgumentError] For an unknown platform
  #
  # @return [String] Type of repo (rpm|deb)
  def repo_type
    case self['platform']
    when /fedora|el-|centos/
      'rpm'
    when /debian|ubuntu|cumulus/
      'deb'
    else
      msg = "#repo_type: repo type not known for platform '#{self['platform']}'"
      raise ArgumentError, msg
    end
  end

  # Tests for a package repo at the platform's path, returning it if it exists
  #
  # @param [String] buildserver_url URL for the buildserver
  # @param [String] package_name Name of the package
  # @param [String] build_version Version of the package
  # @param [String] repo_name Name of the repo to check for the package in
  #
  # @return [String, nil] Path to the package repo if it exists, nil otherwise
  def repo_path_exists(buildserver_url, package_name, build_version, repo_name)
    variant, version, arch, codename = self['platform'].to_array
    variant = 'el' if variant == 'centos'

    repo_path = nil
    case variant
    when /fedora|el|centos/
      fedora_prefix = ((variant == 'fedora') ? 'f' : '')

      link =  "%s/%s/%s/repos/%s/%s%s/%s/%s/" %
        [ buildserver_url, package_name, build_version, variant,
          fedora_prefix, version, repo_name, arch ]
      repo_path = link if link_exists?( link )
    when /debian|ubuntu|cumulus/
      path_candidate = "/root/#{package_name}/#{codename}/#{repo_name}"
      repo_check = exec(
        Beaker::Command.new("[[ -d #{path_candidate} ]]"),
        :acceptable_exit_codes => [0,1] )
      repo_path = path_candidate if repo_check.exit_code == 0
    end
    return repo_path
  end

  # Gets the development build repos list
  #
  # @param [Array<String>] build_repos custom repos to use before our defaults
  #
  # @return [Array<String>] Build repo array, fully flushed out
  def dev_build_repos(build_repos = [])
    package_repos = build_repos.nil? ? [] : [build_repos]
    package_repos.push(['products', 'devel']) if self['platform'] =~ /fedora|el-|centos/
    package_repos.flatten
  end

  # Gets the path to the repo for the given package
  #
  # @param [Array<String>] build_repos names of the repos to check for the package
  # @param [String] buildserver_url URL to the buildserver
  # @param [String] package_name Name of the package
  # @param [String] build_version Version of the package
  #
  # @raise [RuntimeError] if not able to find a package repo on EL platforms
  #
  # @note On Debian-based systems, will default to the 'main' repo, unlike
  #   EL-based ones, which will raise an error
  #
  # @return [String] Path to the repo for the given package
  def repo_path(build_repos, buildserver_url, package_name, build_version)
    repo_path = nil
    package_repos = self.dev_build_repos( build_repos )
    logger.trace("FOSSUtils#install_repo package repos: '#{package_repos}'")
    package_repos.each do |repo|
      repo_path = self.repo_path_exists(
        buildserver_url, package_name, build_version, repo )
      if repo_path
        logger.debug("found repo at #{repo}:#{repo_path}")
        break
      else
        logger.debug("couldn't find link at #{repo}, falling back to next option...")
      end
    end

    case self['platform']
    when /fedora|el-|centos/
      raise "Unable to reach a repo directory at #{repo_path}" unless link_exists?( repo_path )
    when /debian|ubuntu|cumulus/
      if repo_path.nil?
        repo_path = 'main'
        logger.debug("using default repo '#{repo_path}'")
      end
    end

    repo_path
  end

  # Returns the noask file text for Solaris hosts
  #
  # @raise [ArgumentError] If called on a host with a platform that's not Solaris
  #
  # @return [String] the text of the noask file
  def noask_file_text
    variant, version, arch, codename = self['platform'].to_array
    if variant == 'solaris' && version == '10'
      noask = <<NOASK
# Write the noask file to a temporary directory
# please see man -s 4 admin for details about this file:
# http://www.opensolarisforum.org/man/man4/admin.html
#
# The key thing we don't want to prompt for are conflicting files.
# The other nocheck settings are mostly defensive to prevent prompts
# We _do_ want to check for available free space and abort if there is
# not enough
mail=
# Overwrite already installed instances
instance=overwrite
# Do not bother checking for partially installed packages
partial=nocheck
# Do not bother checking the runlevel
runlevel=nocheck
# Do not bother checking package dependencies (We take care of this)
idepend=nocheck
rdepend=nocheck
# DO check for available free space and abort if there isn't enough
space=quit
# Do not check for setuid files.
setuid=nocheck
# Do not check if files conflict with other packages
conflict=nocheck
# We have no action scripts.  Do not check for them.
action=nocheck
# Install to the default base directory.
basedir=default
NOASK
    else
      msg = "noask file text unknown for platform '#{self['platform']}'"
      raise ArgumentError, msg
    end
    noask
  end
end
