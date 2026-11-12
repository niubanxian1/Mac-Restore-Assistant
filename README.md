# Mac Restore Assistant

**A free and open-source utility for MacBook repair professionals.**

Mac Restore Assistant is designed to make DFU mode, Revive, Restore, and device management workflows more accessible, reliable, and convenient for MacBook repair professionals.

## Open-Source Philosophy

> **This project should not belong to a single person. It should grow through shared use, research, and continued improvement by the community.**

Everyone is welcome to use, copy, modify, study, and redistribute this project, including using it as the basis for their own work.

If you fix a bug, improve device compatibility, or develop a useful new feature, contributions via GitHub Pull Requests are always welcome.

**Contributing back is never required, but any valuable contribution is sincerely appreciated.**

Together, we can make MacBook repair tools more capable, stable, and accessible.

## Acknowledgements

Mac Restore Assistant is independently maintained, but its design and implementation have benefited greatly from the ideas, research, documentation, and tooling shared by the Mac repair and DFU community. I am sincerely grateful to the authors, contributors, and maintainers of the following projects and resources. Their willingness to share their work has made projects like this possible.

### Open-Source Projects

- [XRSec/DFU-Tools](https://github.com/XRSec/DFU-Tools)
- [AsahiLinux/macvdmtool](https://github.com/AsahiLinux/macvdmtool)
- [kylejericson/DFU_Tool](https://github.com/kylejericson/DFU_Tool)
- [waynebonc/Popeyes](https://github.com/waynebonc/Popeyes)
- [fcjr/restorekit](https://github.com/fcjr/restorekit)

### DFU Blaster by TwoCanoes

- [Product page](https://twocanoes.com/products/mac/dfu-blaster/)
- [Development history](https://twocanoes.com/products/mac/dfu-blaster/history/)
- [Public downloads](https://bitbucket.org/twocanoes/dfu-blaster-public/downloads/)

Thank you for openly sharing your knowledge, tools, and experience with the community.

## License

This project is licensed under the MIT License.

You are free to use, modify, distribute, and commercially use the project, provided that the copyright and permission notices required by the license are retained.

## Project Status

Mac Restore Assistant 1.0 RC source is available on `main`.

The current RC focuses on per-port Mac repair workflows, privileged Helper
management, passive device observation, calibrated port layouts, and
five-language UI support. Macs require macOS 26 or later.

The published app is an Apple Development build and is not notarized. macOS
therefore requires first-launch approval in System Settings.

## Build from source

Requirements:

- macOS 26 or later
- Xcode 26 or later with the Swift 6 toolchain

Run:

```bash
swift test
swift build -c release
```

The `RestoreLogEngine` dependency is vendored under `Vendor/source`, so a clean
clone does not depend on files outside this repository.
