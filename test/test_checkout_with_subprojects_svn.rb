$:.unshift File.join(File.dirname(__FILE__), '..', 'lib') if $0 == __FILE__

require 'externals/test_case'
require 'externals/ext'
require 'externals/test/rails_app_svn_repository'

module Externals
  module Test
    class TestCheckoutWithSubprojectsSvn < TestCase
      include ExtTestCase

      def test_checkout_with_subproject
        repository = RailsAppSvnRepository.new
        repository.prepare

        workdir = File.join(root_dir, 'test', "tmp", "workdir", "checkout")
        rm_rf_ie workdir
        mkdir_p workdir
        Dir.chdir workdir do
          source = repository.clean_url

          puts "About to checkout #{source}"
          Ext.run "checkout", "--svn", source, 'rails_app'

          Dir.chdir 'rails_app' do
            assert File.exists?('.svn')

            %w(redhillonrails_core acts_as_list).each do |proj|
              puts(ignore_text = `svn propget svn:ignore vendor/plugins`)
              assert(ignore_text =~ /^#{proj}$/)
            end

            puts(ignore_text = `svn propget svn:ignore vendor`)
            assert(ignore_text =~ /^rails$/)

            %w(redhillonrails_core acts_as_list engines).each do |proj|
              assert File.exists?(File.join('vendor', 'plugins', proj, 'lib'))
            end

            assert File.exists?(File.join('vendor', 'rails', 'activerecord', 'lib'))

            assert File.exists?(File.join('vendor', 'rails', '.git'))

            Dir.chdir File.join('vendor', 'rails') do
              heads = File.readlines("heads").map(&:strip)
              assert_equal 3, heads.size
              heads.each do |head|
                assert head =~ /^[0-9a-f]{40}$/
              end

              assert `git show #{heads[0]}` =~
                /^\s*commit\s+#{heads[0]}\s*$/
            end

            assert File.exists?(File.join('modules', 'modules.txt'))

            assert File.read(File.join('modules', 'modules.txt')) =~ /line1 of/

            Dir.chdir File.join('vendor', 'plugins', 'engines') do
              assert(`git branch -a` =~ /^\*\s*edge\s*$/)
              assert(`git branch -a` !~ /^\*\s*master\s*$/)
            end
          end
        end
      end

      def test_update_with_missing_subproject_git
        repository = RailsAppSvnRepository.new
        repository.prepare

        workdir = File.join(root_dir, 'test', "tmp", "workdir", "checkout")
        rm_rf_ie workdir
        mkdir_p workdir
        Dir.chdir workdir do
          source = repository.clean_url

          puts "About to checkout #{source}"
          Ext.run "checkout", "--svn", source, 'rails_app'

          Dir.chdir 'rails_app' do
            pretests = proc do
              assert File.exists?('.svn')
              assert !File.exists?(File.join('vendor', 'plugins', 'ssl_requirement', 'lib'))
              assert File.read(".externals") =~ /rails/
              assert File.read(".externals") !~ /ssl_requirement/
            end

            pretests.call

            #add a project
            workdir2 = File.join("workdir2")
            rm_rf_ie workdir2
            mkdir_p workdir2

            Dir.chdir workdir2 do
              puts "About to checkout #{source}"
              Ext.run "checkout", "--svn", source, 'rails_app'

              Dir.chdir "rails_app" do
                #install a new project
                subproject = GitRepositoryFromInternet.new("ssl_requirement")
                Ext.run "install", subproject.clean_dir

                SvnProject.add_all

                repository.mark_dirty
                puts `svn commit -m "added another subproject (ssl_requirement)"`
              end
            end

            pretests.call

            #update the project and make sure ssl_requirement was added and checked out
            Ext.run "update"
            assert File.read(".externals") =~ /ssl_requirement/
            assert File.exists?(File.join('vendor', 'plugins', 'ssl_requirement', 'lib'))
          end
        end
      end

      def test_update_with_missing_subproject_by_revision_git
        repository = RailsAppSvnRepository.new
        repository.prepare
        subproject = GitRepositoryFromInternet.new("ssl_requirement")
        subproject.prepare
        revision = "aa2dded823f8a9b378c22ba0159971508918928a"
        subproject_name = subproject.name.gsub(".git", "")

        workdir = File.join(root_dir, 'test', "tmp", "workdir", "checkout")
        rm_rf_ie workdir
        mkdir_p workdir
        Dir.chdir workdir do
          source = repository.clean_url

          puts "About to checkout #{source}"
          Ext.run "checkout", "--svn", source, 'rails_app'

          Dir.chdir 'rails_app' do

            pretests = proc do
              assert File.exists?('.svn')
              assert !File.exists?(File.join('vendor', 'plugins', subproject_name, 'lib'))
              assert File.read(".externals") =~ /rails/
              assert File.read(".externals") !~ /#{subproject}/
            end

            pretests.call

            #add a project
            workdir2 = "workdir2"
            rm_rf_ie workdir2
            mkdir_p workdir2

            Dir.chdir workdir2 do

              #install a new project
              puts "About to checkout #{source}"
              Ext.run "checkout", "--svn", source, 'rails_app'

              Dir.chdir "rails_app" do
                Ext.run "install", subproject.clean_dir

                Dir.chdir File.join("vendor", 'plugins', subproject_name) do
                  assert `git show HEAD` !~ /^\s*commit\s*#{revision}\s*$/i
                end
                #freeze it to a revision
                Ext.run "freeze", subproject_name, revision
                Dir.chdir File.join("vendor", 'plugins', subproject_name) do
                  regex = /^\s*commit\s*#{revision}\s*$/i
                  output = `git show HEAD`
                  result = output =~ regex
                  unless result
                    puts "Expecting output to match #{regex} but it was: #{output}"
                  end
                  assert result
                end

                SvnProject.add_all

                repository.mark_dirty
                puts `svn commit -m "added another subproject (#{subproject}) frozen to #{revision}"`
              end
            end

            pretests.call

            #update the project and make sure ssl_requirement was added and checked out at the right revision
            Ext.run "update"
            assert File.read(".externals") =~ /ssl_requirement/

            assert File.exists?(File.join('vendor', 'plugins', subproject_name, 'lib'))

            Dir.chdir File.join("vendor",'plugins', subproject_name) do
              assert `git show HEAD` =~ /^\s*commit\s*#{revision}\s*$/i
            end
          end
        end
      end

      def test_update_with_missing_subproject_svn
        repository = RailsAppSvnRepository.new
        repository.prepare
        subproject = SvnRepositoryFromDump.new("empty_plugin")
        subproject.prepare

        workdir = File.join(root_dir, 'test', "tmp", "workdir", "checkout")
        rm_rf_ie workdir
        mkdir_p workdir
        Dir.chdir workdir do
          source = repository.clean_url

          puts "About to checkout #{source}"
          Ext.run "checkout", "--svn", source, 'rails_app'

          Dir.chdir 'rails_app' do
            pretests = proc do
              assert File.exists?('.svn')
              assert !File.exists?(File.join('vendor', 'plugins', subproject.name, 'lib'))
              assert File.read(".externals") =~ /rails/
              assert File.read(".externals") !~ /empty_plugin/
            end

            pretests.call

            #add a project
            workdir2 = File.join "workdir2", "svn"
            rm_rf_ie workdir2
            mkdir_p workdir2

            Dir.chdir workdir2 do
              puts "About to checkout #{source}"
              Ext.run "checkout", "--svn", source, 'rails_app'

              Dir.chdir 'rails_app' do
                #install a new project
                Ext.run "install", "--svn", subproject.clean_url

                SvnProject.add_all

                repository.mark_dirty
                puts `svn commit -m "added another subproject (#{subproject.name})"`
              end
            end

            pretests.call

            #update the project and make sure ssl_requirement was added and checked out
            Ext.run "update"
            assert File.read(".externals") =~ /empty_plugin/
            assert File.exists?(File.join('vendor', 'plugins', subproject.name, 'lib'))
          end
        end
      end

      def test_export_with_subproject
        repository = RailsAppSvnRepository.new
        repository.prepare

        workdir = File.join(root_dir, 'test', "tmp", "workdir", "export")
        rm_rf_ie workdir
        mkdir_p workdir
        Dir.chdir workdir do
          source = repository.clean_url

          puts "About to export #{source}"
          Ext.run "export", "--svn", source, 'rails_app'

          Dir.chdir 'rails_app' do
            assert !File.exists?('.svn')

            Dir.chdir File.join('vendor', 'rails') do
              heads = File.readlines("heads").map(&:strip)
              assert_equal 3, heads.size
              heads.each do |head|
                assert head =~ /^[0-9a-f]{40}$/
              end

              assert `git show #{heads[0]}` !~
                /^\s*commit\s+#{heads[0]}\s*$/
            end

            %w(redhillonrails_core acts_as_list).each do |proj|
              puts "filethere? #{proj}: #{File.exists?(File.join('vendor', 'plugins', proj, 'lib'))}"
              if !File.exists?(File.join('vendor', 'plugins', proj, 'lib'))
                puts "here"
              end
              assert File.exists?(File.join('vendor', 'plugins', proj, 'lib'))
            end

            %w(redhillonrails_core).each do |proj|
              assert !File.exists?(File.join('vendor', 'plugins',proj, '.svn'))
            end

            assert File.exists?(File.join('vendor', 'rails', 'activerecord', 'lib'))
          end
        end
      end

      def test_uninstall
        return
        Dir.chdir File.join(root_dir, 'test') do
          Dir.chdir 'workdir' do
            `mkdir checkout`
            Dir.chdir 'checkout' do
              #source = File.join(root_dir, 'test', 'workdir', 'rails_app')
              source = repository_dir('svn')

              if windows?
                source = source.gsub(/\\/, "/")
                #source.gsub!(/^[A-Z]:[\/\\]/, "")
              end
              source = "file:///#{source}"

              puts "About to checkout #{source}"
              Ext.run "checkout", "--svn", source, "rails_app"

              Dir.chdir 'rails_app' do
                mp = Ext.new.main_project

                projs = %w(foreign_key_migrations redhillonrails_core acts_as_list)
                projs_i = projs.dup
                projs_ni = []

                #let's uninstall acts_as_list
                Ext.run "uninstall", "acts_as_list"

                projs_ni << projs_i.delete('acts_as_list')

                mp.assert_e_dne_i_ni proc{|a|assert(a)}, projs, [], projs_i, projs_ni

                Ext.run "uninstall", "-f", "foreign_key_migrations"

                projs_ni << projs_i.delete('foreign_key_migrations')

                projs_dne = []
                projs_dne << projs.delete('foreign_key_migrations')

                mp.assert_e_dne_i_ni proc{|a|assert(a)}, projs, projs_dne, projs_i, projs_ni
              end
            end
          end
        end
      end

    end
  end
end