# Desk Check's Homebrew formula has one source: this file in the desk-check repository.
# The tap (marcellovictorino/homebrew-tap) copies it at each release tag and fills in its own
# url, sha256 and revision. In desk-check the url and checksum are placeholders; change install,
# test and caveats in desk-check, never in the tap.
# Desk Check is built on the person's own Mac during `brew install`, with Apple's
# command line tools. Built here, it is signed ad hoc for this Mac and opens without
# a macOS warning, so no Apple developer account is needed.
class DeskCheck < Formula
  desc "Menu bar posture coach that tells you how to move your screen and desk"
  homepage "https://github.com/marcellovictorino/desk-check"
  url "https://github.com/marcellovictorino/desk-check/archive/refs/tags/v0.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/marcellovictorino/desk-check.git", branch: "main"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    # Build with the command line tools when they are installed, as Homebrew itself does,
    # so the result is the same whether or not Xcode is present.
    ENV["DEVELOPER_DIR"] = MacOS::CLT::PKG_PATH if MacOS::CLT.installed?
    # Desk Check builds in the Swift 6 language mode, which needs Swift 6 (command line tools 16 or later).
    swift_major = Utils.safe_popen_read("xcrun", "swift", "--version")[/Swift version (\d+)/, 1].to_i
    if swift_major < 6
      odie "Desk Check needs Swift 6 or later to build, and this Mac has Swift #{swift_major}. " \
           "Update the command line tools (version 16 or later, which needs macOS 14.5 or later) " \
           "with `xcode-select --install` or in System Settings > General > Software Update, " \
           "then run brew install again."
    end
    system "scripts/build-app.sh", version.to_s, prefix
    pkgshare.install "Tests/verify-app.sh"
    # desk-check quits a copy left running by an older install, then opens this one; --version prints the version.
    (bin/"desk-check").write File.read("scripts/desk-check.sh").gsub("@APP@", "#{opt_prefix}/DeskCheck.app")
  end

  def caveats
    <<~EOS
      Start Desk Check with:
        desk-check
      It lives in the menu bar and has no Dock icon.
      After brew upgrade, run desk-check again: it quits the old version and opens the new one.

      To find it in Spotlight and Launchpad as well:
        ln -sf "#{opt_prefix}/DeskCheck.app" ~/Applications/
    EOS
  end

  test do
    system pkgshare/"verify-app.sh", prefix/"DeskCheck.app"
    assert_equal version.to_s, shell_output("#{bin}/desk-check --version").strip
  end
end
