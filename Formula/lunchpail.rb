class Lunchpail < Formula
  desc "Metal-aware Apple silicon virtual machine runtime"
  homepage "https://github.com/metaspartan/lunchpail"
  license "Apache-2.0"
  head "https://github.com/metaspartan/lunchpail.git", branch: "main"

  depends_on xcode: ["16.0", :build]
  depends_on arch: :arm64
  depends_on macos: :sequoia

  def install
    %w[lunchpail lunchpail-metal-probe LunchpailMetalShim].each do |product|
      system "swift", "build", "--configuration", "release", "--disable-sandbox",
             "--product", product
    end
    build_dir = Utils.safe_popen_read(
      "swift", "build", "--configuration", "release", "--show-bin-path"
    ).strip

    bin.install "#{build_dir}/lunchpail"
    bin.install "#{build_dir}/Lunchpail_LunchpailAPI.bundle"
    (libexec/"lunchpail").install "#{build_dir}/lunchpail-metal-probe"
    (libexec/"lunchpail").install "#{build_dir}/libLunchpailMetalShim.dylib"

    system "/usr/bin/codesign", "--force", "--sign", "-",
           "#{libexec}/lunchpail/lunchpail-metal-probe"
    system "/usr/bin/codesign", "--force", "--sign", "-",
           "#{libexec}/lunchpail/libLunchpailMetalShim.dylib"
    system "/usr/bin/codesign", "--force", "--sign", "-", "--entitlements",
           "#{buildpath}/Resources/lunchpail.entitlements", "#{bin}/lunchpail"

    generate_completions_from_executable(bin/"lunchpail", "--generate-completion-script")
  end

  test do
    assert_match "Metal-aware macOS VMs", shell_output("#{bin}/lunchpail --help")
    assert_match "stock", shell_output("#{bin}/lunchpail metal profiles")
    assert_path_exists bin/"Lunchpail_LunchpailAPI.bundle/openapi.yaml"
  end
end
