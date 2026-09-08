{ config, inputs, pkgs, username, ... }:

let
  clavisCore = pkgs.callPackage ../../packages/clavis-core.nix {
    src = inputs.clavis;
  };
  clavisConfig = pkgs.callPackage ../../packages/clavis-config.nix {
    src = inputs.clavis;
  };
  clavisOcr = pkgs.writeShellApplication {
    name = "clavis-ocr";
    runtimeInputs = with pkgs; [
      coreutils
      grim
      libnotify
      tesseract5
      wl-clipboard
    ];
    text = ''
      if [[ $# -ne 1 || ! $1 =~ ^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$ ]]; then
        echo "usage: clavis-ocr WIDTHxHEIGHT+X+Y" >&2
        exit 2
      fi
      grimGeometry="''${BASH_REMATCH[3]},''${BASH_REMATCH[4]} ''${BASH_REMATCH[1]}x''${BASH_REMATCH[2]}"

      errorFile="$(mktemp)"
      trap 'rm -f "$errorFile"' EXIT

      if ! recognizedText="$(
        set -o pipefail
        grim -g "$grimGeometry" - \
          | tesseract stdin stdout -l chi_sim+eng --psm 6 2>"$errorFile"
      )"; then
        errorMessage="$(tail -n 1 "$errorFile")"
        notify-send --urgency=critical "OCR 失败" "''${errorMessage:-无法截取或识别所选区域}"
        cat "$errorFile" >&2
        exit 1
      fi

      if [[ -z "''${recognizedText//[[:space:]]/}" ]]; then
        notify-send "OCR 未识别到文字" "请重新选择文字更清晰的区域"
        exit 3
      fi

      printf '%s' "$recognizedText" | wl-copy
      notify-send "OCR 完成" "识别文字已复制到剪贴板"
    '';
  };
  clavisScreenshot = pkgs.writeShellApplication {
    name = "clavis-screenshot";
    runtimeInputs = with pkgs; [ grim libnotify wl-clipboard ];
    text = ''
      if [[ $# -ne 1 || ! $1 =~ ^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$ ]]; then
        echo "usage: clavis-screenshot WIDTHxHEIGHT+X+Y" >&2
        exit 2
      fi
      grimGeometry="''${BASH_REMATCH[3]},''${BASH_REMATCH[4]} ''${BASH_REMATCH[1]}x''${BASH_REMATCH[2]}"

      if ! grim -g "$grimGeometry" - | wl-copy; then
        notify-send --urgency=critical "截图失败" "无法截取所选区域"
        exit 1
      fi
      notify-send "截图完成" "所选区域已复制到剪贴板"
    '';
  };
  clavisHiddenWifi = pkgs.writeShellApplication {
    name = "clavis-hidden-wifi";
    runtimeInputs = with pkgs; [ coreutils networkmanager ];
    text = ''
      if [[ $# -ne 2 || ( $1 != "open" && $1 != "secure" ) ]]; then
        echo "usage: clavis-hidden-wifi open|secure SSID" >&2
        exit 2
      fi

      securityMode="$1"
      ssid="$2"
      ssidBytes="$(printf '%s' "$ssid" | wc -c)"
      if (( ssidBytes == 0 || ssidBytes > 32 )) || [[ "$ssid" == *$'\n'* || "$ssid" == *$'\r'* ]]; then
        echo "SSID must contain 1 to 32 bytes without line breaks" >&2
        exit 2
      fi

      password=""
      if [[ "$securityMode" == "secure" ]]; then
        if ! IFS= read -r password; then
          echo "missing password on stdin" >&2
          exit 2
        fi

        passwordBytes="$(printf '%s' "$password" | wc -c)"
        validPassword=false
        if (( passwordBytes >= 8 && passwordBytes <= 63 )); then
          validPassword=true
        elif (( passwordBytes == 64 )) && [[ "$password" =~ ^[0-9A-Fa-f]{64}$ ]]; then
          validPassword=true
        fi
        if [[ "$validPassword" != true ]]; then
          echo "WPA/WPA2 password must be 8-63 bytes or 64 hexadecimal digits" >&2
          exit 2
        fi
      fi

      umask 077
      uuid="$(< /proc/sys/kernel/random/uuid)"
      connectionName="Clavis hidden: $ssid"
      connectionCreated=false
      connectionActivated=false
      secretFile=""

      cleanup() {
        if [[ "$connectionCreated" == true && "$connectionActivated" != true ]]; then
          nmcli --wait 10 connection delete uuid "$uuid" >/dev/null 2>&1 || true
        fi
        if [[ -n "$secretFile" ]]; then
          rm -f -- "$secretFile"
        fi
      }
      trap cleanup EXIT

      connectionArgs=(
        --wait 10 connection add
        type wifi
        con-name "$connectionName"
        ifname "*"
        ssid "$ssid"
        wifi.hidden yes
        connection.uuid "$uuid"
        connection.autoconnect no
      )
      if [[ "$securityMode" == "secure" ]]; then
        connectionArgs+=(wifi-sec.key-mgmt wpa-psk)
      fi
      nmcli "''${connectionArgs[@]}"
      connectionCreated=true

      activationArgs=(--wait 30 connection up uuid "$uuid")
      if [[ "$securityMode" == "secure" ]]; then
        runtimeDir="''${XDG_RUNTIME_DIR:-/tmp}"
        secretFile="$(mktemp "$runtimeDir/clavis-hidden-wifi.XXXXXX")"
        chmod 600 "$secretFile"
        printf '802-11-wireless-security.psk:%s\n' "$password" > "$secretFile"
        unset password
        activationArgs+=(passwd-file "$secretFile")
      fi

      nmcli "''${activationArgs[@]}"
      nmcli --wait 10 connection modify uuid "$uuid" connection.autoconnect yes
      connectionActivated=true
    '';
  };
  clavisTools = pkgs.writeShellApplication {
    name = "clavis-tools";
    runtimeInputs = with pkgs; [ quickshell systemd ];
    text = ''
      clavisPid="$(systemctl --user show clavis-shell.service --property MainPID --value)"
      if [[ -z "$clavisPid" || "$clavisPid" == "0" ]]; then
        echo "clavis-shell.service is not running" >&2
        exit 1
      fi
      exec qs ipc --pid "$clavisPid" call keystone tools
    '';
  };
  clavisToggleComponents = pkgs.writeShellApplication {
    name = "clavis-toggle-components";
    runtimeInputs = with pkgs; [ quickshell systemd ];
    text = ''
      clavisPid="$(systemctl --user show clavis-shell.service --property MainPID --value)"
      if [[ -z "$clavisPid" || "$clavisPid" == "0" ]]; then
        echo "clavis-shell.service is not running" >&2
        exit 1
      fi
      exec qs ipc --pid "$clavisPid" call display toggleComponents
    '';
  };
  clavisShell = pkgs.writeShellApplication {
    name = "clavis-shell";
    runtimeInputs = [
      clavisCore
      clavisHiddenWifi
      clavisOcr
      clavisScreenshot
      config.programs.gpu-screen-recorder.package
      config.programs.niri.package
    ] ++ (with pkgs; [
      quickshell
      kitty
      asusctl
      awww
      bash
      brightnessctl
      ddcutil
      ffmpeg
      glib.bin
      gnome-system-monitor
      grim
      hyprpicker
      jq
      libnotify
      matugen
      playerctl
      pavucontrol
      pulseaudio
      python3
      rclone
      swayidle
      swaylock
      systemd
      which
      wl-clipboard
      wl-gammarelay-rs
    ]);
    text = ''
      export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin:$HOME/.local/state/nix/profiles/home-manager/home-path/bin:$PATH"

      if [[ -z "''${NIRI_SOCKET:-}" ]]; then
        for socket in "''${XDG_RUNTIME_DIR:-/run/user/$UID}"/niri.*.sock; do
          if [[ -S "$socket" ]]; then
            export NIRI_SOCKET="$socket"
            break
          fi
        done
      fi

      export QML_IMPORT_PATH="${clavisCore}/lib/qt-6/qml:${pkgs.qt6Packages.qt5compat}/lib/qt-6/qml:${pkgs.qt6Packages.qtlottie}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
      export QML2_IMPORT_PATH="$QML_IMPORT_PATH"
      export GSETTINGS_SCHEMA_DIR="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
      colorFile="''${XDG_CACHE_HOME:-$HOME/.cache}/quickshell-dev-colorscheme/colors.json"
      if [[ ! -s "$colorFile" ]]; then
        bash "${clavisConfig}/scripts/theme/generate_quickshell_colors.sh" \
          --color "#669cb1" --output "$colorFile" || true
      fi
      exec qs --no-duplicate --no-color --path "${clavisConfig}"
    '';
  };
  clavisShellWatchdog = pkgs.writeShellApplication {
    name = "clavis-shell-watchdog";
    runtimeInputs = with pkgs; [ coreutils quickshell systemd ];
    text = ''
      # Give Quickshell time to load the QML tree before probing it.
      sleep 30
      failedChecks=0
      while :; do
        if ! systemctl --user is-active --quiet clavis-shell.service; then
          failedChecks=0
          sleep 15
          continue
        fi

        pid="$(systemctl --user show clavis-shell.service -p MainPID --value)"
        if [[ -n "$pid" && "$pid" != 0 ]] \
          && timeout 8 qs ipc --pid "$pid" call lock isLocked >/dev/null 2>&1; then
          failedChecks=0
        else
          failedChecks=$((failedChecks + 1))
          if (( failedChecks >= 2 )); then
            systemctl --user restart clavis-shell.service
            failedChecks=0
            sleep 10
          fi
        fi
        sleep 15
      done
    '';
  };
in
{
  programs.gpu-screen-recorder.enable = true;

  environment.systemPackages = with pkgs; [
    clavisCore
    clavisShell
    clavisTools
    clavisToggleComponents
    qt6Packages.qt5compat
    qt6Packages.qtlottie
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    lxgw-wenkai-screen
    material-symbols
  ];

  fonts.fontconfig.localConf = ''
    <alias binding="strong">
      <family>LXGW WenKai GB Screen</family>
      <prefer><family>LXGW WenKai Screen</family></prefer>
    </alias>
  '';

  systemd.user.services.wl-gammarelay = {
    description = "Wayland gamma and brightness relay";
    after = [ "niri.service" ];
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    unitConfig.ConditionUser = username;
    serviceConfig = {
      ExecStart = "${pkgs.wl-gammarelay-rs}/bin/wl-gammarelay-rs run";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.user.services.clavis-shell = {
    description = "StatIndet Clavis Quickshell";
    after = [ "niri.service" "wl-gammarelay.service" ];
    wants = [ "wl-gammarelay.service" ];
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    unitConfig.ConditionUser = username;
    serviceConfig = {
      ExecStart = "${clavisShell}/bin/clavis-shell";
      Restart = "on-failure";
      RestartSec = 2;
      OOMPolicy = "stop";
      # Recover before a runaway QML/media surface can starve the session.
      MemoryMax = "2G";
      MemoryHigh = "1536M";
    };
  };

  systemd.user.services.clavis-shell-watchdog = {
    description = "Clavis Quickshell health watchdog";
    after = [ "clavis-shell.service" "niri.service" ];
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    unitConfig.ConditionUser = username;
    serviceConfig = {
      ExecStart = "${clavisShellWatchdog}/bin/clavis-shell-watchdog";
      Restart = "always";
      RestartSec = 5;
    };
  };
}
