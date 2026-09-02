{ config, lib, pkgs, username, ... }:

let
  comfyui = pkgs.callPackage ../../packages/comfyui.nix { };
  clavisLauncher = pkgs.writeShellApplication {
    name = "clavis-launcher";
    runtimeInputs = with pkgs; [ quickshell systemd ];
    text = ''
      clavisPid="$(systemctl --user show clavis-shell.service --property MainPID --value)"
      if [[ -z "$clavisPid" || "$clavisPid" == "0" ]]; then
        echo "clavis-shell.service is not running" >&2
        exit 1
      fi
      exec qs ipc --pid "$clavisPid" call launcher toggle
    '';
  };
  clipboardHistory = pkgs.writeShellApplication {
    name = "clipboard-history";
    runtimeInputs = with pkgs; [ cliphist fuzzel libnotify wl-clipboard ];
    text = ''
      if [[ "''${1:-}" == "clear" ]]; then
        confirmation="$(
          printf '%s\n' "确认清空全部历史" \
            | fuzzel --dmenu --only-match --prompt="剪贴板 > " --lines=1
        )"
        if [[ "$confirmation" == "确认清空全部历史" ]]; then
          cliphist wipe
          notify-send "剪贴板历史" "历史记录已清空"
        fi
        exit 0
      fi

      selection="$(
        cliphist list \
          | fuzzel --dmenu --only-match --no-run-if-empty \
              --prompt="剪贴板 > " --placeholder="搜索历史记录" \
              --with-nth=2 --match-nth=2
      )"
      printf '%s\n' "$selection" | cliphist decode | wl-copy
    '';
  };
  wechatLauncher = pkgs.writeShellApplication {
    name = "wechat-launcher";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      exec systemd-run --user --collect --quiet --setenv=DISPLAY=:0 \
        ${pkgs.wechat}/bin/wechat "$@"
    '';
  };
  imageMimeTypes = [
    "image/apng" "image/avif" "image/bmp" "image/gif" "image/heic"
    "image/jpeg" "image/png" "image/svg+xml" "image/tiff" "image/webp"
  ];
  videoMimeTypes = [
    "video/3gpp" "video/mp2t" "video/mp4" "video/mpeg" "video/ogg"
    "video/quicktime" "video/webm" "video/x-flv" "video/x-matroska"
    "video/x-msvideo" "video/x-ms-wmv"
  ];
  audioMimeTypes = [
    "audio/aac" "audio/flac" "audio/m4a" "audio/mp4" "audio/mpeg"
    "audio/ogg" "audio/opus" "audio/wav" "audio/webm" "audio/x-wav"
  ];
  archiveMimeTypes = [
    "application/gzip" "application/vnd.rar" "application/x-7z-compressed"
    "application/x-bzip" "application/x-bzip-compressed-tar"
    "application/x-compressed-tar" "application/x-rar"
    "application/x-rar-compressed" "application/x-tar" "application/x-xz"
    "application/x-xz-compressed-tar" "application/zip"
  ];
  defaultApplications =
    lib.genAttrs imageMimeTypes (_: [ "org.gnome.Loupe.desktop" ])
    // lib.genAttrs (videoMimeTypes ++ audioMimeTypes) (_: [ "io.github.celluloid_player.Celluloid.desktop" ])
    // lib.genAttrs archiveMimeTypes (_: [ "org.gnome.FileRoller.desktop" ])
    // {
      "application/pdf" = [ "org.gnome.Papers.desktop" ];
      "inode/directory" = [ "thunar.desktop" ];
    };
  resolveNixosConfig = ''
    repo="''${NIXOS_CONFIG_DIR:-}"
    if [[ -z "$repo" ]]; then
      if ! repo="$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null)"; then
        echo "run this command inside the NixOS repository or set NIXOS_CONFIG_DIR" >&2
        exit 1
      fi
    fi
    if [[ ! -f "$repo/flake.nix" ]]; then
      echo "NixOS flake not found at: $repo" >&2
      exit 1
    fi
  '';
  nixosCheck = pkgs.writeShellApplication {
    name = "nixos-check";
    runtimeInputs = [ pkgs.nix config.programs.niri.package ];
    text = ''
      ${resolveNixosConfig}
      niri validate -c "$repo/hosts/ODT/niri-config.kdl"
      nix eval --raw "path:$repo#nixosConfigurations.ODT.config.system.build.toplevel.drvPath"
      echo
    '';
  };

  nixosBuild = pkgs.writeShellApplication {
    name = "nixos-build";
    runtimeInputs = [ pkgs.nix config.programs.niri.package ];
    text = ''
      ${resolveNixosConfig}
      niri validate -c "$repo/hosts/ODT/niri-config.kdl"
      nix build --no-link --print-out-paths \
        --option substituters "https://cache.nixos.org https://niri.cachix.org" \
        --option http-connections 8 \
        --option http2 false \
        --option max-substitution-jobs 4 \
        --option download-attempts 5 \
        --option stalled-download-timeout 30 \
        "path:$repo#nixosConfigurations.ODT.config.system.build.toplevel"
    '';
  };

  nixosSwitch = pkgs.writeShellApplication {
    name = "nixos-switch";
    runtimeInputs = [ pkgs.nix config.programs.niri.package ];
    text = ''
      ${resolveNixosConfig}
      niri validate -c "$repo/hosts/ODT/niri-config.kdl"
      output="$(nix build --no-link --print-out-paths \
        --option substituters "https://cache.nixos.org https://niri.cachix.org" \
        --option http-connections 8 \
        --option http2 false \
        --option max-substitution-jobs 4 \
        --option download-attempts 5 \
        --option stalled-download-timeout 30 \
        "path:$repo#nixosConfigurations.ODT.config.system.build.toplevel")"
      sudo nix-env --profile /nix/var/nix/profiles/system --set "$output"
      sudo "$output/bin/switch-to-configuration" switch
    '';
  };

  nixosRollback = pkgs.writeShellApplication {
    name = "nixos-rollback";
    text = ''
      sudo nixos-rebuild switch --rollback
    '';
  };
in
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";

    users.${username} = { lib, ... }: {
      home.activation.seedNiriRuntimeFiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p "$HOME/.config/niri/dms"
        if [[ ! -e "$HOME/.config/niri/clavis-effects.kdl" ]]; then
          run ${pkgs.coreutils}/bin/install -m 600 \
            ${./clavis-effects.kdl} "$HOME/.config/niri/clavis-effects.kdl"
        fi
        if [[ ! -e "$HOME/.config/niri/dms/cursor.kdl" ]]; then
          run ${pkgs.coreutils}/bin/install -m 600 \
            ${./dms/cursor.kdl} "$HOME/.config/niri/dms/cursor.kdl"
        fi
      '';

      services.blueman-applet.enable = true;

      services.cliphist = {
        enable = true;
        allowImages = true;
        extraOptions = [
          "-max-dedupe-search" "100"
          "-max-items" "500"
          "-min-store-length" "1"
        ];
        systemdTargets = [ "graphical-session.target" ];
      };

      services.udiskie = {
        enable = true;
        automount = true;
        notify = true;
        tray = "auto";
        settings = {
          program_options.file_manager = "${pkgs.thunar}/bin/thunar";
          icon_names.media = [
            "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/scalable/devices/drive-removable-media.svg"
          ];
        };
      };

      systemd.user.services.udiskie.Service.Environment = [ "LC_MESSAGES=C.UTF-8" ];

      home = {
        inherit username;
        homeDirectory = "/home/${username}";
        stateVersion = "26.05";
        enableNixpkgsReleaseCheck = false;
        sessionPath = [ "$HOME/.local/state/nix/profiles/home-manager/home-path/bin" ];
        sessionVariables = {
          EDITOR = "hx";
          VISUAL = "hx";
          TERMINAL = "kitty";
          BROWSER = "firefox";
        };
        packages = [
          clavisLauncher
          clipboardHistory
          pkgs.discord
          nixosCheck
          nixosBuild
          nixosSwitch
          nixosRollback
          pkgs.nodejs_22
          wechatLauncher
          pkgs.wmctrl
          comfyui.setup
          comfyui.launch
        ];
      };

      systemd.user.services.comfyui = {
        Unit = {
          Description = "ComfyUI image generation server";
          Documentation = "https://github.com/Comfy-Org/ComfyUI";
          ConditionPathExists = "%h/AI/ComfyUI/.venv/bin/python";
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${comfyui.launch}/bin/comfyui-launch";
          WorkingDirectory = "%h/AI/ComfyUI";
          Restart = "on-failure";
          RestartSec = 5;
          Environment = [ "PYTHONUNBUFFERED=1" ];
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      xdg = {
        desktopEntries.wechat = {
          name = "wechat";
          genericName = "wechat";
          comment = "Messaging and calling app";
          exec = "${wechatLauncher}/bin/wechat-launcher %U";
          icon = "wechat";
          terminal = false;
          categories = [ "Network" "InstantMessaging" ];
          settings.StartupNotify = "true";
        };
        configFile."niri/config.kdl".source = ./niri-config.kdl;
        configFile."fcitx5/profile" = {
          force = true;
          text = ''
          [Groups/0]
          Name=默认
          Default Layout=us
          DefaultIM=pinyin

          [Groups/0/Items/0]
          Name=keyboard-us
          Layout=

          [Groups/0/Items/1]
          Name=pinyin
          Layout=

          [GroupOrder]
          0=默认
          '';
        };
        configFile."fcitx5/conf/classicui.conf".text = ''
          [General]
          Vertical Candidate List=False
          WheelForPaging=True
          Font=LXGW WenKai GB Screen 12
          MenuFont=LXGW WenKai GB Screen 12
          TrayFont=JetBrainsMono Nerd Font 11
          Theme=Clavis
          DarkTheme=Clavis
          UseDarkTheme=True
          UseAccentColor=False
          PerScreenDPI=True
          EnableFractionalScale=True
        '';
        dataFile."fcitx5/themes/Clavis/theme.conf".text = ''
          [Metadata]
          Name=Clavis
          Version=1
          Author=ODT
          Description=Clavis Material 3 dark theme
          ScaleWithDPI=True

          [InputPanel]
          Font=LXGW WenKai GB Screen 12
          NormalColor=#bfc8cc
          HighlightCandidateColor=#003544
          HighlightColor=#dee3e6
          HighlightBackgroundColor=#1b2023
          Spacing=4
          PageButtonAlignment=Last Candidate

          [InputPanel/TextMargin]
          Left=10
          Right=10
          Top=7
          Bottom=7

          [InputPanel/ContentMargin]
          Left=2
          Right=2
          Top=2
          Bottom=2

          [InputPanel/Background]
          Color=#171c1f
          BorderColor=#40484c
          BorderWidth=1

          [InputPanel/Background/Margin]
          Left=1
          Right=1
          Top=1
          Bottom=1

          [InputPanel/Highlight]
          Color=#88d0ec

          [InputPanel/Highlight/Margin]
          Left=10
          Right=10
          Top=7
          Bottom=7

          [Menu/Background]
          Color=#171c1f
          BorderColor=#40484c
          BorderWidth=1

          [Menu/Background/Margin]
          Left=1
          Right=1
          Top=1
          Bottom=1

          [Menu/ContentMargin]
          Left=2
          Right=2
          Top=2
          Bottom=2

          [Menu/Highlight]
          Color=#354a53

          [Menu/Highlight/Margin]
          Left=8
          Right=8
          Top=6
          Bottom=6

          [Menu/Separator]
          Color=#40484c

          [Menu/TextMargin]
          Left=8
          Right=8
          Top=6
          Bottom=6
        '';
        dataFile."applications/rog-control-center.desktop".text = ''
          [Desktop Entry]
          Hidden=true
        '';
        mimeApps = {
          enable = true;
          inherit defaultApplications;
        };
      };

      programs = {
        home-manager.enable = true;

        fuzzel = {
          enable = true;
          settings = {
            main = {
              font = "LXGW WenKai GB Screen:size=12";
              width = 72;
              lines = 12;
              tabs = 4;
              horizontal-pad = 18;
              vertical-pad = 10;
              inner-pad = 8;
              line-height = 24;
              layer = "overlay";
              match-mode = "fzf";
            };
            border = {
              width = 1;
              radius = 8;
            };
            colors = {
              background = "171c1ff2";
              text = "dce4e8ff";
              prompt = "8fc9ddff";
              placeholder = "899296ff";
              input = "f0f4f6ff";
              match = "80d5cfff";
              selection = "354a53ff";
              selection-text = "f0f4f6ff";
              selection-match = "9cf1ebff";
              counter = "899296ff";
              border = "59676cff";
            };
          };
        };

        bash = {
          enable = true;
          enableCompletion = true;
          initExtra = ''
            case ":$PATH:" in
              *":$HOME/.local/state/nix/profiles/home-manager/home-path/bin:"*) ;;
              *) export PATH="$HOME/.local/state/nix/profiles/home-manager/home-path/bin:$PATH" ;;
            esac

            PS1='\[\e[38;2;143;201;221m\]ODT\[\e[38;2;137;146;150m\] · \[\e[38;2;220;228;232m\]\w\[\e[38;2;143;201;221m\] ❯ \[\e[0m\]'
          '';
          historyControl = [ "ignoredups" "ignorespace" ];
          historySize = 10000;
        };

        git = {
          enable = true;
          settings = {
            core.editor = "hx";
            init.defaultBranch = "main";
          };
        };

        kitty = {
          enable = true;
          settings = {
            font_family = "JetBrainsMono Nerd Font Mono";
            symbol_map = "U+4E00-U+9FFF Noto Sans Mono CJK SC";
            font_size = 11.5;
            window_padding_width = 16;
            window_padding_height = 14;
            window_border_width = "1pt";
            active_border_color = "#294955";
            inactive_border_color = "#202629";
            background_opacity = "0.94";
            hide_window_decorations = true;
            confirm_os_window_close = 0;
            scrollback_lines = 10000;
            copy_on_select = true;
            enable_audio_bell = false;
            visual_bell_duration = 0;
            cursor_shape = "beam";
            cursor_blink_interval = 0.55;
            cursor_stop_blinking_after = 0;
            foreground = "#dce4e8";
            background = "#101417";
            selection_foreground = "#101417";
            selection_background = "#8fc9dd";
            cursor = "#8fc9dd";
            color0 = "#202629";
            color1 = "#ffb4ab";
            color2 = "#9bd67d";
            color3 = "#e5c76b";
            color4 = "#8fc9dd";
            color5 = "#d5b4e8";
            color6 = "#80d5cf";
            color7 = "#c4c7c9";
            color8 = "#6f797d";
            color9 = "#ffdad6";
            color10 = "#b6f397";
            color11 = "#ffdf8d";
            color12 = "#bee9f7";
            color13 = "#efd5ff";
            color14 = "#9cf1eb";
            color15 = "#f0f4f6";
            tab_bar_edge = "top";
            tab_bar_style = "powerline";
            tab_powerline_style = "slanted";
            tab_bar_background = "#101417";
            active_tab_foreground = "#101417";
            active_tab_background = "#8fc9dd";
            inactive_tab_foreground = "#899296";
            inactive_tab_background = "#202629";
          };
        };

        fastfetch = {
          enable = true;
          package = pkgs.fastfetch;
          settings = {
            logo = {
              type = "builtin";
              source = "nixos";
              padding = { right = 3; };
              color = {
                "1" = "cyan";
                "2" = "blue";
              };
            };
            display = {
              separator = "  › ";
              brightColor = true;
              color = {
                keys = "cyan";
                title = "cyan";
                separator = "blue";
                output = "white";
              };
            };
            modules = [
              "title"
              "separator"
              { type = "os"; key = "󰣇 系统"; }
              { type = "host"; key = "󰌢 设备"; }
              { type = "kernel"; key = "󰒋 内核"; }
              { type = "uptime"; key = "󰅐 运行"; }
              { type = "packages"; key = "󰏖 软件包"; }
              { type = "wm"; key = " 窗管"; }
              { type = "display"; key = "󰍹 显示"; }
              { type = "shell"; key = "󰆍 Shell"; }
              { type = "terminal"; key = " 终端"; }
              { type = "cpu"; key = " 处理器"; }
              { type = "gpu"; key = "󰢮 显卡"; }
              { type = "memory"; key = " 内存"; }
              { type = "disk"; key = "󰋊 磁盘"; }
              { type = "battery"; key = "󰁹 电池"; }
              "break"
              "colors"
            ];
          };
        };
      };
    };
  };
}
