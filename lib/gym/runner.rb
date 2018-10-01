require 'pty'
require 'open3'
require 'fileutils'
require 'shellwords'

module Gym
  class Runner
    # @return (String) The path to the resulting ipa
    def run
      clear_old_files

      build_app
      verify_archive

      FileUtils.mkdir_p(Gym.config[:output_directory])

      if Gym.project.ios? || Gym.project.tvos?
        package_app
        fix_package
        compress_and_move_dsym
        path = move_ipa
        move_manifest
        move_app_thinning
        move_app_thinning_size_report
        move_apps_folder

        path
      elsif Gym.project.mac?
        compress_and_move_dsym
        copy_mac_app
      end
    end

    #####################################################
    # @!group Printing out things
    #####################################################

    # @param [Array] An array containing all the parts of the command
    def print_command(command, title)
      rows = command.map do |c|
        current = c.to_s.dup
        next unless current.length > 0

        match_default_parameter = current.match(/(-.*) '(.*)'/)
        if match_default_parameter
          # That's a default parameter, like `-project 'Name'`
          match_default_parameter[1, 2]
        else
          current.gsub!("| ", "\| ") # as the | will somehow break the terminal table
          [current, ""]
        end
      end

      puts Terminal::Table.new(
        title: title.green,
        headings: ["Option", "Value"],
        rows: rows.delete_if { |c| c.to_s.empty? }
      )
    end

    private

    #####################################################
    # @!group The individual steps
    #####################################################

    def clear_old_files
      return unless Gym.config[:use_legacy_build_api]
      if File.exist?(PackageCommandGenerator.ipa_path)
        File.delete(PackageCommandGenerator.ipa_path)
      end
    end

    def fix_package
      return unless Gym.config[:use_legacy_build_api]
      Gym::XcodebuildFixes.swift_library_fix
      Gym::XcodebuildFixes.watchkit_fix
      Gym::XcodebuildFixes.watchkit2_fix
    end

    def mark_archive_as_built_by_gym(archive_path)
      escaped_archive_path = archive_path.shellescape
      system("xattr -w info.fastlane.generated_by_gym 1 #{escaped_archive_path}")
    end

    # Builds the app and prepares the archive
    def build_app
      command = BuildCommandGenerator.generate
      print_command(command, "Generated Build Command") if $verbose
      FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: true,
                                      print_command: !Gym.config[:silent],
                                              error: proc do |output|
                                                ErrorHandler.handle_build_error(output)
                                              end)

      mark_archive_as_built_by_gym(BuildCommandGenerator.archive_path)
      UI.success "Successfully stored the archive. You can find it in the Xcode Organizer."
      UI.verbose("Stored the archive in: " + BuildCommandGenerator.archive_path)
    end

    # Makes sure the archive is there and valid
    def verify_archive
      # from https://github.com/fastlane/gym/issues/115
      if (Dir[BuildCommandGenerator.archive_path + "/*"]).count == 0
        ErrorHandler.handle_empty_archive
      end
    end

    def package_app
      command = PackageCommandGenerator.generate
      print_command(command, "Generated Package Command") if $verbose

      FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: false,
                                      print_command: !Gym.config[:silent],
                                              error: proc do |output|
                                                ErrorHandler.handle_package_error(output)
                                              end)
    end

    def compress_and_move_dsym
      return unless PackageCommandGenerator.dsym_path

      # Compress and move the dsym file
      containing_directory = File.expand_path("..", PackageCommandGenerator.dsym_path)

      available_dsyms = Dir.glob("#{containing_directory}/*.dSYM")
      UI.message "Compressing #{available_dsyms.count} dSYM(s)" unless Gym.config[:silent]

      output_path = File.expand_path(File.join(Gym.config[:output_directory], Gym.config[:output_name] + ".app.dSYM.zip"))
      command = "cd '#{containing_directory}' && zip -r '#{output_path}' *.dSYM"
      Helper.backticks(command, print: !Gym.config[:silent])

      puts "" # new line

      UI.success "Successfully exported and compressed dSYM file"
    end

    # Moves over the binary and dsym file to the output directory
    # @return (String) The path to the resulting ipa file
    def move_ipa
      FileUtils.mv(PackageCommandGenerator.ipa_path, File.expand_path(Gym.config[:output_directory]), force: true)
      ipa_path = File.expand_path(File.join(Gym.config[:output_directory], File.basename(PackageCommandGenerator.ipa_path)))

      UI.success "Successfully exported and signed the ipa file:"
      UI.message ipa_path
      ipa_path
    end

    # Copies the .app from the archive into the output directory
    def copy_mac_app
      app_path = Dir[File.join(BuildCommandGenerator.archive_path, "Products/Applications/*.app")].last
      UI.crash!("Couldn't find application in '#{BuildCommandGenerator.archive_path}'") unless app_path

      FileUtils.cp_r(app_path, File.expand_path(Gym.config[:output_directory]), remove_destination: true)
      app_path = File.join(Gym.config[:output_directory], File.basename(app_path))

      UI.success "Successfully exported the .app file:"
      UI.message app_path
      app_path
    end

    # Move the manifest.plist if exists into the output directory
    def move_manifest
      if File.exist?(PackageCommandGenerator.manifest_path)
        FileUtils.mv(PackageCommandGenerator.manifest_path, File.expand_path(Gym.config[:output_directory]), force: true)
        manifest_path = File.join(File.expand_path(Gym.config[:output_directory]), File.basename(PackageCommandGenerator.manifest_path))

        UI.success "Successfully exported the manifest.plist file:"
        UI.message manifest_path
        manifest_path
      end
    end

    # Move the app-thinning.plist file into the output directory
    def move_app_thinning
      if File.exist?(PackageCommandGenerator.app_thinning_path)
        FileUtils.mv(PackageCommandGenerator.app_thinning_path, File.expand_path(Gym.config[:output_directory]), force: true)
        app_thinning_path = File.join(File.expand_path(Gym.config[:output_directory]), File.basename(PackageCommandGenerator.app_thinning_path))

        UI.success "Successfully exported the app-thinning.plist file:"
        UI.message app_thinning_path
        app_thinning_path
      end
    end

    # Move the App Thinning Size Report.txt file into the output directory
    def move_app_thinning_size_report
      if File.exist?(PackageCommandGenerator.app_thinning_size_report_path)
        FileUtils.mv(PackageCommandGenerator.app_thinning_size_report_path, File.expand_path(Gym.config[:output_directory]), force: true)
        app_thinning_size_report_path = File.join(File.expand_path(Gym.config[:output_directory]), File.basename(PackageCommandGenerator.app_thinning_size_report_path))

        UI.success "Successfully exported the App Thinning Size Report.txt file:"
        UI.message app_thinning_size_report_path
        app_thinning_size_report_path
      end
    end

    # Move the Apps folder to the output directory
    def move_apps_folder
      if Dir.exist?(PackageCommandGenerator.apps_path)
        FileUtils.mv(PackageCommandGenerator.apps_path, File.expand_path(Gym.config[:output_directory]), force: true)
        apps_path = File.join(File.expand_path(Gym.config[:output_directory]), File.basename(PackageCommandGenerator.apps_path))

        UI.success "Successfully exported Apps folder:"
        UI.message apps_path
        apps_path
      end
    end

    private

    def find_archive_path
      if Gym.config[:use_legacy_build_api]
        BuildCommandGenerator.archive_path
      else
        Dir.glob(File.join(BuildCommandGenerator.build_path, "*.ipa")).last
      end
    end
  end
end
