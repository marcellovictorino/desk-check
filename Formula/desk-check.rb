# Desk Check is built on the person's own Mac during `brew install`, with Apple's
# command line tools. Built here, it is signed ad hoc for this Mac and opens without
# a macOS warning, so no Apple developer account is needed.
class DeskCheck < Formula
  desc "Menu bar posture coach that tells you how to move your screen and desk"
  homepage "https://github.com/marcellovictorino/desk-check"
  url "https://github.com/marcellovictorino/desk-check.git", tag: "v0.1.0"
  license "MIT"
  head "https://github.com/marcellovictorino/desk-check.git", branch: "main"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    # Build with the command line tools when they are installed, as Homebrew itself does,
    # so the result is the same whether or not Xcode is present.
    ENV["DEVELOPER_DIR"] = MacOS::CLT::PKG_PATH if MacOS::CLT.installed?
    system "scripts/build-app.sh", version.to_s, prefix
    pkgshare.install "Tests/verify-app.sh"
    (bin/"desk-check").write <<~SH
      #!/bin/sh
      exec open "#{opt_prefix}/DeskCheck.app"
    SH
  end

  def caveats
    <<~EOS
      Start Desk Check with:
        desk-check
      It lives in the menu bar and has no Dock icon.

      To find it in Spotlight and Launchpad as well:
        ln -sf "#{opt_prefix}/DeskCheck.app" ~/Applications/
    EOS
  end

  test do
    system pkgshare/"verify-app.sh", prefix/"DeskCheck.app"
  end
end
