VirtualCamera tweak. Replaces the camera's image/video output with an arbitrary image or video file. Tested on iOS 15 - 17

## Usage

After installation, open the **VCam** app from the Home Screen. Use **Chọn ảnh** or **Chọn video**, then enable the VCam switch. The app copies the selected media, updates the tweak preferences, and reloads the replacement automatically.

## Build on Windows

This repository includes a GitHub Actions workflow because Theos requires a Linux or macOS build environment.

1. Push the repository to GitHub.
2. Open the repository's **Actions** tab and run **Build tweak** (or push a commit).
3. Open the completed workflow run, download the `vcam-deb` artifact, and copy the `.deb` file to the device.
4. Install it with Sileo/Zebra, or with `dpkg -i` over SSH.

The package is configured for rootless jailbreaks (`iphoneos-arm64`).

This works by hooking into `mediaserverd`, which is responsible for, among other things, connecting to the camera hardware and forwarding image data to interested clients (such as user-installed apps). VCam works in apps even if they don't have tweak injection

This is POC stage. The filepath to the "replacement media" is hardcoded in `image_utils.m`. Memory leaks kill `mediaserverd` every 30s

**image file** 
---
<img src=".imgs/image.png"  width="50%">

**video file**
---
<img src=".imgs/video.gif" width="50%">
