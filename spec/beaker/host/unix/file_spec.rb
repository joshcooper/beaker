require 'spec_helper'

module Beaker
  describe Unix::File do
    class UnixFileTest
      include Unix::File

      def initialize(hash, logger)
        @hash = hash
        @logger = logger
      end

      def [](k)
        @hash[k]
      end

      def to_s
        "me"
      end

      def logger
        @logger
      end

    end

    let (:opts)     { @opts || {} }
    let (:logger)   { double( 'logger' ).as_null_object }
    let (:platform) {
      if @platform
        { 'platform' => Beaker::Platform.new( @platform) }
      else
        { 'platform' => Beaker::Platform.new( 'osx-10.9-x86_64' ) }
      end
    }
    let (:instance) { UnixFileTest.new(opts.merge(platform), logger) }

    describe '#repo_path_exists?' do

      it 'returns nil if the repo_path does not pass the test (el based)' do
        @platform = 'el-7-x86_64'
        allow( instance ).to receive( :link_exists? ) { false }

        repo_path = instance.repo_path_exists(
          'bs_url', 'pkg_name', 'pkg_version', 'repo_name' )
        expect( repo_path ).to be_nil
      end

      it 'returns the candidate path if the test is passed (el based)' do
        @platform = 'el-7-x86_64'
        allow( instance ).to receive( :link_exists? ) { true }

        repo_path = instance.repo_path_exists(
          'bs_url', 'pkg_name', 'pkg_version', 'repo_name' )
        expect( repo_path ).to match( /repos/ )
      end

      it 'returns nil if the repo_path does not pass the test (non-el based)' do
        @platform = 'ubuntu-14.04-x86_64'
        expect( Beaker::Command ).to receive( :new )
        test_result_mock = Object.new
        expect( test_result_mock ).to receive( :exit_code ) { 1 }
        expect( instance ).to receive( :exec ) { test_result_mock }

        repo_path = instance.repo_path_exists(
          'bs_url', 'pkg_name', 'pkg_version', 'repo_name' )
        expect( repo_path ).to be_nil
      end

      it 'returns candidate path if the test is passed (non-el based)' do
        @platform = 'ubuntu-14.04-x86_64'
        expect( Beaker::Command ).to receive( :new )
        test_result_mock = Object.new
        expect( test_result_mock ).to receive( :exit_code ) { 0 }
        expect( instance ).to receive( :exec ) { test_result_mock }

        repo_path = instance.repo_path_exists(
          'bs_url', 'pkg_name', 'pkg_version', 'repo_name' )
        expect( repo_path ).to match( /root/ )
      end

      it 'prepends f to the version in the URL and rpm for fedora platforms' do
        @platform = 'fedora-77-x86_64'
        allow( instance ).to receive( :link_exists? ) { true }

        repo_path = instance.repo_path_exists(
          'bs_url', 'pkg_name', 'pkg_version', 'repo_name' )
        expect( repo_path ).to match( /#{Regexp.escape("/repos/fedora/f77/")}/ )
      end

      it 'uses el as the variant in the URL for centos platforms' do
        @platform = 'centos-7-x86_64'
        allow( instance ).to receive( :link_exists? ) { true }

        repo_path = instance.repo_path_exists(
          'bs_url', 'pkg_name', 'pkg_version', 'repo_name' )
        expect( repo_path ).to match( /#{Regexp.escape("/repos/el/7/")}/ )
      end


    end

    describe '#dev_build_repos' do

      it 'defaults to products or devel repos for el-based platforms' do
        allow( instance ).to receive( :[] ).with( 'platform' ) { 'el-7' }
        repos = instance.dev_build_repos
        expect( repos ).to be === ['products', 'devel']
      end

      it 'does not provide default repos for non el-based platforms' do
        allow( instance ).to receive( :[] ).with( 'platform' ) { 'osx' }
        repos = instance.dev_build_repos
        expect( repos ).to be === []
      end

      it 'allows ordered customization of repos based on build_repos param' do
        build_repos = ['PC17', 'yomama', 'McGuyver', 'McGruber', 'panama']
        repos = instance.dev_build_repos(build_repos)
        expect( repos ).to be === build_repos
      end
    end

    describe '#repo_path' do

      it 'goes through repos in order, looking for one that exists' do
        repos = ['1', '2', '3', '4']
        allow( instance ).to receive( :dev_build_repos ) { repos }

        repos.each do |repo|
          expect( instance ).to receive( :repo_path_exists ).with(
            anything, anything, anything, repo
          ).ordered.once.and_return( nil )
        end

        instance.repo_path( repos, 'bs_url', 'pkg_name', 'pkg_version' )
      end

      it 'errors if no repos are found for el-based platforms' do
        @platform = 'el-7-x86_64'
        allow( instance ).to receive( :dev_build_repos ).and_return( [] )
        allow( instance ).to receive( :link_exists? ).and_return( false )

        expect {
          instance.repo_path( [], 'bs_url', 'pkg_name', 'pkg_version' )
        }.to raise_error( RuntimeError, /^Unable\ to\ reach\ a\ repo\ dir/ )
      end

      it 'uses default repo "main" if no repos are found for debian-based platforms' do
        @platform = 'debian-7-x86_64'
        allow( instance ).to receive( :dev_build_repos ).and_return( [] )

        expect( logger ).to receive( :debug ).with( /^using\ default\ repo/ )
        repo_path = instance.repo_path( [], 'bs_url', 'pkg_name', 'pkg_version' )
        expect( repo_path ).to be === 'main'
      end

      it 'stops early and returns if a repo does exist' do
        repos = ['1', '2', '3', '4', '5']
        no_list = ['1', '2']
        not_hit_list = ['4', '5']
        allow( instance ).to receive( :dev_build_repos ) { repos }

        no_list.each do |no_repo|
          expect( instance ).to receive( :repo_path_exists ).with(
            anything, anything, anything, no_repo
          ).ordered.once.and_return( nil )
        end

        answer = 'repo_path_faked_up'
        expect( instance ).to receive( :repo_path_exists ).with(
          anything, anything, anything, '3'
        ).and_return( answer )

        not_hit_list.each do |not_hit_repo|
          expect( instance ).to receive( :repo_path_exists ).with(
            anything, anything, anything, not_hit_repo
          ).exactly( 0 ).times
        end

        expect( logger ).to receive( :debug ).with( /^found\ repo\ at\ 3\:/ )
        test = instance.repo_path( repos, 'bs_url', 'pkg_name', 'pkg_version' )
        expect( test ).to be === answer
      end

    end

    describe '#repo_type' do

      it 'returns correctly for el-based platforms' do
        @platform = 'centos-6-x86_64'
        expect( instance.repo_type ).to be === 'rpm'
      end

      it 'returns correctly for debian-based platforms' do
        @platform = 'debian-6-x86_64'
        expect( instance.repo_type ).to be === 'deb'
      end

      it 'errors for all other platform types' do
        @platform = 'eos-4-x86_64'
        expect {
          instance.repo_type
        }.to raise_error( ArgumentError, /repo\ type\ not\ known/ )
      end
    end

    describe '#package_config_dir' do

      it 'returns correctly for el-based platforms' do
        @platform = 'centos-6-x86_64'
        expect( instance.package_config_dir ).to be === '/etc/yum.repos.d/'
      end

      it 'returns correctly for debian-based platforms' do
        @platform = 'debian-6-x86_64'
        expect( instance.package_config_dir ).to be === '/etc/apt/sources.list.d'
      end

      it 'errors for all other platform types' do
        @platform = 'eos-4-x86_64'
        expect {
          instance.package_config_dir
        }.to raise_error( ArgumentError, /package\ config\ dir\ unknown/ )
      end
    end

    describe '#repo_filename' do

      it 'sets the el portion correctly for centos platforms' do
        @platform = 'centos-5-x86_64'
        allow( instance ).to receive( :is_pe? ) { false }
        filename = instance.repo_filename( 'pkg_name', 'pkg_version7' )
        expect( filename ).to match( /sion7\-el\-/ )
      end

      it 'builds the filename correctly for el-based platforms' do
        @platform = 'el-21-x86_64'
        allow( instance ).to receive( :is_pe? ) { false }
        filename = instance.repo_filename( 'pkg_name', 'pkg_version8' )
        correct = 'pl-pkg_name-pkg_version8-el-21-x86_64.repo'
        expect( filename ).to be === correct
      end

      it 'adds in the PE portion of the filename correctly for el-based PE hosts' do
        @platform = 'el-21-x86_64'
        allow( instance ).to receive( :is_pe? ) { true }
        filename = instance.repo_filename( 'pkg_name', 'pkg_version9' )
        correct = 'pl-pkg_name-pkg_version9-repos-pe-el-21-x86_64.repo'
        expect( filename ).to be === correct
      end

      it 'builds the filename correctly for debian-based platforms' do
        @platform = 'debian-8-x86_64'
        filename = instance.repo_filename( 'pkg_name', 'pkg_version9' )
        correct = 'pl-pkg_name-pkg_version9-jessie.list'
        expect( filename ).to be === correct
      end

      it 'errors for non-el or debian-based platforms' do
        @platform = 'freebsd-22-x86_64'
        expect {
          instance.repo_filename( 'pkg_name', 'pkg_version' )
        }. to raise_error( ArgumentError, /repo\ filename\ pattern\ not\ known/ )
      end
    end

    describe '#noask_file_text' do

      it 'errors on non-solaris platforms' do
        @platform = 'cumulus-4000-x86_64'
        expect {
          instance.noask_file_text
        }.to raise_error( ArgumentError, /^noask\ file\ text\ unknown/ )
      end

      it 'errors on solaris versions other than 10' do
        @platform = 'solaris-11-x86_64'
        expect {
          instance.noask_file_text
        }.to raise_error( ArgumentError, /^noask\ file\ text\ unknown/ )
      end

      it 'returns the noask file correctly for solaris 10' do
        @platform = 'solaris-10-x86_64'
        text = instance.noask_file_text
        expect( text ).to match( /instance\=overwrite/ )
        expect( text ).to match( /space\=quit/ )
        expect( text ).to match( /basedir\=default/ )
      end
    end
  end
end
