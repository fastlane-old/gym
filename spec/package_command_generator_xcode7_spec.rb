describe Gym do
  describe Gym::PackageCommandGeneratorXcode7 do
    it "works with the example project with no additional parameters" do
      options = { project: "./examples/standard/Example.xcodeproj" }
      Gym.config = FastlaneCore::Configuration.create(Gym::Options.available_options, options)

      result = Gym::PackageCommandGeneratorXcode7.generate
      expect(result).to eq([
        "/usr/bin/xcrun #{Gym::XcodebuildFixes.wrap_xcodebuild} -exportArchive",
        "-exportOptionsPlist '#{Gym::PackageCommandGeneratorXcode7.config_path}'",
        "-archivePath '#{Gym::BuildCommandGenerator.archive_path}'",
        "-exportPath '#{Gym::PackageCommandGeneratorXcode7.temporary_output_path}'",
        ""
      ])
    end

    it "generates a valid plist file we need" do
      options = { project: "./examples/standard/Example.xcodeproj" }
      Gym.config = FastlaneCore::Configuration.create(Gym::Options.available_options, options)

      result = Gym::PackageCommandGeneratorXcode7.generate
      config_path = Gym::PackageCommandGeneratorXcode7.config_path

      require 'plist'
      expect(Plist.parse_xml(config_path)).to eq({
        'method' => "app-store",
        'uploadBitcode' => false,
        'uploadSymbols' => true
      })
    end

    it "reads user export plist" do
      options = { project: "./examples/standard/Example.xcodeproj", export_options: "./examples/standard/ExampleExport.plist" }
      Gym.config = FastlaneCore::Configuration.create(Gym::Options.available_options, options)

      result = Gym::PackageCommandGeneratorXcode7.generate
      config_path = Gym::PackageCommandGeneratorXcode7.config_path

      require 'plist'
      expect(Plist.parse_xml(config_path)).to eq({
        'embedOnDemandResourcesAssetPacksInBundle' => true,
        'manifest' => {
          'appURL' => 'https://www.example.com/Example.ipa',
          'displayImageURL' => 'https://www.example.com/display.png',
          'fullSizeImageURL' => 'https://www.example.com/fullSize.png'
        },
        'method' => 'ad-hoc'
      })
      expect(Gym.config[:export_method]).to eq("ad-hoc")
      expect(Gym.config[:include_symbols]).to be_nil
      expect(Gym.config[:include_bitcode]).to be_nil
      expect(Gym.config[:export_team_id]).to be_nil
    end

    it "reads user export plist and override some parameters" do
      options = {
        project: "./examples/standard/Example.xcodeproj",
        export_options: "./examples/standard/ExampleExport.plist",
        export_method: "app-store",
        include_symbols: false,
        include_bitcode: true,
        export_team_id: "1234567890"
      }
      Gym.config = FastlaneCore::Configuration.create(Gym::Options.available_options, options)

      result = Gym::PackageCommandGeneratorXcode7.generate
      config_path = Gym::PackageCommandGeneratorXcode7.config_path

      require 'plist'
      expect(Plist.parse_xml(config_path)).to eq({
        'embedOnDemandResourcesAssetPacksInBundle' => true,
        'manifest' => {
          'appURL' => 'https://www.example.com/Example.ipa',
          'displayImageURL' => 'https://www.example.com/display.png',
          'fullSizeImageURL' => 'https://www.example.com/fullSize.png'
        },
        'method' => 'app-store',
        'uploadSymbols' => false,
        'uploadBitcode' => true,
        'teamID' => '1234567890'
      })
    end

    it "reads export options from hash" do
      options = {
        project: "./examples/standard/Example.xcodeproj",
        export_options: {
          embedOnDemandResourcesAssetPacksInBundle: false,
          manifest: {
            appURL: "https://example.com/My App.ipa",
            displayImageURL: "https://www.example.com/display image.png",
            fullSizeImageURL: "https://www.example.com/fullSize image.png"
          },
          method: "enterprise",
          uploadSymbols: false,
          uploadBitcode: true,
          teamID: "1234567890"
        },
        export_method: "app-store",
        include_symbols: true,
        include_bitcode: false,
        export_team_id: "ASDFGHJK"
      }
      Gym.config = FastlaneCore::Configuration.create(Gym::Options.available_options, options)

      result = Gym::PackageCommandGeneratorXcode7.generate
      config_path = Gym::PackageCommandGeneratorXcode7.config_path

      require 'plist'
      expect(Plist.parse_xml(config_path)).to eq({
        'embedOnDemandResourcesAssetPacksInBundle' => false,
        'manifest' => {
          'appURL' => 'https://example.com/My%20App.ipa',
          'displayImageURL' => 'https://www.example.com/display%20image.png',
          'fullSizeImageURL' => 'https://www.example.com/fullSize%20image.png'
        },
        'method' => 'app-store',
        'uploadSymbols' => true,
        'uploadBitcode' => false,
        'teamID' => 'ASDFGHJK'
      })
    end

    it "doesn't store bitcode/symbols information for non app-store builds" do
      options = { project: "./examples/standard/Example.xcodeproj", export_method: 'ad-hoc' }
      Gym.config = FastlaneCore::Configuration.create(Gym::Options.available_options, options)

      result = Gym::PackageCommandGeneratorXcode7.generate
      config_path = Gym::PackageCommandGeneratorXcode7.config_path

      require 'plist'
      expect(Plist.parse_xml(config_path)).to eq({
        'method' => "ad-hoc"
      })
    end

    it "uses a temporary folder to store the resulting ipa file" do
      options = { project: "./examples/standard/Example.xcodeproj" }
      Gym.config = FastlaneCore::Configuration.create(Gym::Options.available_options, options)

      result = Gym::PackageCommandGeneratorXcode7.generate
      expect(Gym::PackageCommandGeneratorXcode7.temporary_output_path).to match(%r{#{Dir.tmpdir}/gym.+\.gym_output})
      expect(Gym::PackageCommandGeneratorXcode7.manifest_path).to match(%r{#{Dir.tmpdir}/gym.+\.gym_output/manifest.plist})
      expect(Gym::PackageCommandGeneratorXcode7.app_thinning_path).to match(%r{#{Dir.tmpdir}/gym.+\.gym_output/app-thinning.plist})
      expect(Gym::PackageCommandGeneratorXcode7.app_thinning_size_report_path).to match(%r{#{Dir.tmpdir}/gym.+\.gym_output/App Thinning Size Report.txt})
      expect(Gym::PackageCommandGeneratorXcode7.apps_path).to match(%r{#{Dir.tmpdir}/gym.+\.gym_output/Apps})
    end
  end
end
