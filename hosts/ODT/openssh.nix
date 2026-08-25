{ enableRemoteAccess, ... }:
{
  services.openssh = {
    enable = enableRemoteAccess;
    openFirewall = enableRemoteAccess;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
