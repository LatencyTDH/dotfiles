{ user, ... }:

{
  # The Nix installer manages the daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "x86_64-darwin"; # use x86_64-darwin for Intel CPU

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  system.stateVersion = 6;
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = true;  # auto-hide the menu bar
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click
  };
  nix-homebrew = {
    enable = true;
    autoMigrate = true; # take over an existing Intel Homebrew installation
    inherit user;
  };
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = false; # keep rebuilds fast; run `brew update` manually
    onActivation.extraFlags = [ "--force" ];
    taps = [
      { name = "hashicorp/tap"; trusted = true; }
    ];
    brews = [
      "herdr"
      "openvpn"
      { name = "hashicorp/tap/terraform"; trusted = true; }
    ];
    casks = [
      "wezterm"
      "claude-code"
    ];
  };
}
