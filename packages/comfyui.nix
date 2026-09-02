{ pkgs }:

let
  root = "$HOME/AI/ComfyUI";
in
{
  setup = pkgs.writeShellApplication {
    name = "comfyui-setup";
    runtimeInputs = with pkgs; [ git python3 ];
    text = ''
      root="''${COMFYUI_HOME:-${root}}"
      repo="https://github.com/Comfy-Org/ComfyUI.git"

      mkdir -p "$root"
      if [[ ! -d "$root/.git" ]]; then
        if [[ -n "$(ls -A "$root" 2>/dev/null)" ]]; then
          echo "ComfyUI directory is not empty: $root" >&2
          exit 1
        fi
        git clone --depth=1 "$repo" "$root"
      else
        git -C "$root" pull --ff-only
      fi

      if [[ ! -x "$root/.venv/bin/python" ]]; then
        python -m venv "$root/.venv"
      fi
      "$root/.venv/bin/python" -m pip install --upgrade pip
      "$root/.venv/bin/python" -m pip install torch torchvision torchaudio \
        --extra-index-url https://download.pytorch.org/whl/cu130
      "$root/.venv/bin/python" -m pip install -r "$root/requirements.txt"
      "$root/.venv/bin/python" -m pip install -r "$root/manager_requirements.txt"

      mkdir -p "$root/models/checkpoints" "$root/models/loras" \
        "$root/models/vae" "$root/models/controlnet" "$root/input" "$root/output"
      mkdir -p "$root/user/__manager"
      if [[ ! -e "$root/user/__manager/config.ini" ]]; then
        printf '%s\n' '[default]' 'use_uv = False' > "$root/user/__manager/config.ini"
      fi
      echo "ComfyUI is ready at $root"
      echo "Put checkpoints in $root/models/checkpoints"
      echo "Start with: systemctl --user start comfyui.service"
    '';
  };

  launch = pkgs.writeShellApplication {
    name = "comfyui-launch";
    runtimeInputs = [ pkgs.python3 pkgs.stdenv.cc.cc pkgs.zlib ];
    text = ''
      root="''${COMFYUI_HOME:-${root}}"
      if [[ ! -x "$root/.venv/bin/python" ]]; then
        echo "ComfyUI is not installed. Run comfyui-setup first." >&2
        exit 1
      fi
      cd "$root"
      export PATH="$root/.venv/bin:$PATH"
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:${pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc pkgs.zlib ]}:''${LD_LIBRARY_PATH:-}"
      exec "$root/.venv/bin/python" main.py \
        --listen 127.0.0.1 --port 8188 \
        --enable-cors-header http://127.0.0.1:8000 \
        --enable-manager "$@"
    '';
  };
}
