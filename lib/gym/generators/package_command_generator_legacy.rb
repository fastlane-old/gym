# encoding: utf-8
# from http://stackoverflow.com/a/9857493/445598
# because of
# `incompatible encoding regexp match (UTF-8 regexp with ASCII-8BIT string) (Encoding::CompatibilityError)`

module Gym
  # Responsible for building the fully working xcodebuild command on Xcode < 7
  #
  # Because of a known bug in PackageApplication Perl script used by Xcode the packaging process is performed with
  # a patched version of the script.
  class PackageCommandGeneratorLegacy
    class << self
      def generate
        parts = prefix
        parts += options
        parts += pipe

        parts
      end

      def prefix
        ["/usr/bin/xcrun #{XcodebuildFixes.patch_package_application} -v"]
      end

      def options
        options = []

        options << Shellwords.escape(appfile_path)
        options << "-o '#{ipa_path}'"
        options << "exportFormat ipa"

        if Gym.config[:provisioning_profile_path]
          options << "--embed '#{Gym.config[:provisioning_profile_path]}'"
        end

        if Gym.config[:codesigning_identity]
          options << "--sign '#{Gym.config[:codesigning_identity]}'"
        end

        options
      end

      def pipe
        [""]
      end

      def appfile_path
        path = Dir.glob("#{BuildCommandGenerator.archive_path}/Products/Applications/*.app").first
        path ||= Dir[BuildCommandGenerator.archive_path + "/**/*.app"].last

        return path
      end

      # We export it to the temporary folder and move it over to the actual output once it's finished and valid
      def ipa_path
        File.join(BuildCommandGenerator.build_path, "#{Gym.config[:output_name]}.ipa")
      end

      # The path the the dsym file for this app. Might be nil
      def dsym_path
        Dir[BuildCommandGenerator.archive_path + "/**/*.app.dSYM"].last
      end
    end
  end
end
