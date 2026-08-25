{ pkgs, ... }:
{
  services = {
    asusd.enable = true;
    power-profiles-daemon.enable = true;
    thermald.enable = true;
    upower.enable = true;
    fwupd.enable = true;
  };

  systemd.services = {
    asusd.wantedBy = [ "multi-user.target" ];

    asus-laptop-policy = {
      description = "Apply ASUS laptop battery and power policy";
      wantedBy = [ "multi-user.target" ];
      after = [ "asusd.service" ];
      requires = [ "asusd.service" ];
      path = [ pkgs.asusctl ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        asusctl battery limit 80
        asusctl profile set --ac Balanced
        asusctl profile set --battery Quiet
        if [[ "$(</sys/class/power_supply/ADP0/online)" == "1" ]]; then
          asusctl profile set Balanced
        else
          asusctl profile set Quiet
        fi
      '';
    };
  };
}
