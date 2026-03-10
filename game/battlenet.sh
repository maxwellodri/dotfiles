#!/bin/bash


# Environment variables
export __GL_SHADER_DISK_CACHE="1"
export __GL_SHADER_DISK_CACHE_PATH="/home/maxwell/Games/battlenet"
export LD_LIBRARY_PATH="/home/maxwell/.local/share/lutris/runtime/Ubuntu-18.04-i686:/home/maxwell/.local/share/lutris/runtime/steam/i386/lib/i386-linux-gnu:/home/maxwell/.local/share/lutris/runtime/steam/i386/lib:/home/maxwell/.local/share/lutris/runtime/steam/i386/usr/lib/i386-linux-gnu:/home/maxwell/.local/share/lutris/runtime/steam/i386/usr/lib:/home/maxwell/.local/share/lutris/runtime/Ubuntu-18.04-x86_64:/home/maxwell/.local/share/lutris/runtime/steam/amd64/lib/x86_64-linux-gnu:/home/maxwell/.local/share/lutris/runtime/steam/amd64/lib:/home/maxwell/.local/share/lutris/runtime/steam/amd64/usr/lib/x86_64-linux-gnu:/home/maxwell/.local/share/lutris/runtime/steam/amd64/usr/lib"
export LC_ALL=""
export WINEDEBUG="-all"
export DXVK_LOG_LEVEL="error"
export UMU_LOG="1"
export WINEARCH="win64"
export WINE="/usr/share/steam/compatibilitytools.d/proton-ge-custom/files/bin/wine"
export WINE_MONO_CACHE_DIR="/home/maxwell/.local/share/lutris/runners/wine/proton-ge-custom/files/mono"
export WINE_GECKO_CACHE_DIR="/home/maxwell/.local/share/lutris/runners/wine/proton-ge-custom/files/gecko"
export WINEPREFIX="/home/maxwell/Games/battlenet"
export WINEESYNC="1"
export WINEFSYNC="1"
export WINE_FULLSCREEN_FSR="1"
export DXVK_NVAPIHACK="0"
export DXVK_ENABLE_NVAPI="1"
export PROTON_BATTLEYE_RUNTIME="/home/maxwell/.local/share/lutris/runtime/battleye_runtime"
export PROTON_EAC_RUNTIME="/home/maxwell/.local/share/lutris/runtime/eac_runtime"
export PROTON_DXVK_D3D8="1"
export WINEDLLOVERRIDES="d3dcompiler_33,d3dcompiler_34,d3dcompiler_35,d3dcompiler_36,d3dcompiler_37,d3dcompiler_38,d3dcompiler_39,d3dcompiler_40,d3dcompiler_41,d3dcompiler_42,d3dcompiler_43,d3dcompiler_46,d3dcompiler_47,d3dx10,d3dx10_33,d3dx10_34,d3dx10_35,d3dx10_36,d3dx10_37,d3dx10_38,d3dx10_39,d3dx10_40,d3dx10_41,d3dx10_42,d3dx10_43,d3dx11_42,d3dx11_43,d3dx9_24,d3dx9_25,d3dx9_26,d3dx9_27,d3dx9_28,d3dx9_29,d3dx9_30,d3dx9_31,d3dx9_32,d3dx9_33,d3dx9_34,d3dx9_35,d3dx9_36,d3dx9_37,d3dx9_38,d3dx9_39,d3dx9_40,d3dx9_41,d3dx9_42,d3dx9_43=n;winemenubuilder="
export WINE_LARGE_ADDRESS_AWARE="1"
export TERM="xterm"

# Working Directory
cd '/home/maxwell/Games/battlenet/drive_c/Program Files (x86)/Battle.net'

# Command
gamemoderun /home/maxwell/.local/share/lutris/runtime/umu/umu-run '/home/maxwell/Games/battlenet/drive_c/Program Files (x86)/Battle.net/Battle.net.exe'