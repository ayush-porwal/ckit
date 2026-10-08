# CKit

A menu bar app for Apple’s `container` CLI. Click the Ckit icon to start the service, create a Linux machine, or open Terminal in one.

## Requirements

- An Apple Silicon Mac running macOS 26 or later
- [Apple’s container CLI](https://github.com/apple/container), installed and set up

The first kernel setup happens in Terminal. After that, CKit can start the service for you.

## Install

Download the release, open the DMG, and drag CKit to Applications. Open it from there.

macOS may block the download because the build is not notarized. If you trust it, allow it in **System Settings → Privacy & Security → Open Anyway**.

## Use

Click Ckit icon

- **Start Service** and **Stop Service** run the container service. Stopping it stops every machine.
- **Create Machine…** asks for a name, CPUs, and memory. Alpine 3.22 is ready to use. Ubuntu 24.04 is prepared on your Mac the first time, which can take a few minutes. You can also type your own image.
- **Check Image** looks up an image before creating anything. Close the window to cancel.
- Each machine has **Start**, **Stop**, **Open Terminal**, and **Delete**. Delete removes the machine and its disk.
- Quitting CKit leaves the service and your machines running.

New machines do not mount your home folder. **Start after creating** is on by default.

## Build

Open `CKit.xcodeproj` in Xcode 27 and run the CKit scheme.
