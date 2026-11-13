# Fenix-8: Transformation watch face

A clean digital watch face for the Garmin fenix 8, written in Monkey C for Connect IQ.

![Preview](docs/preview.png)

*Left: normal view. Right: AMOLED always-on (low power) view. The preview is a design mockup; real fonts on the watch are Garmin's own.*

## Features

- Large time: hours in white, minutes in your accent colour; follows the watch's 12/24 hour setting
- Date line, for example **FRI** 13 NOV
- Left bezel arc: battery level (green above 50%, amber above 20%, red below)
- Right bezel arc: progress towards your daily step goal (turns green when reached)
- Heart rate, steps and battery percentage row
- Unread notification count (only shown when you have some)
- AMOLED burn-in protection: in always-on mode it shows a small dim time that shifts position every minute
- Accent colour setting: Gold, Teal, Orange, Red, Blue or Green (change it in the Garmin Connect app)
- Layout scales to every fenix 8 screen size

## Supported devices

| Device | Product ID |
|---|---|
| fenix 8 AMOLED 43mm | `fenix843mm` |
| fenix 8 AMOLED 47mm / 51mm | `fenix847mm` |
| fenix 8 Solar 47mm | `fenix8solar47mm` |
| fenix 8 Solar 51mm | `fenix8solar51mm` |

Other devices (for example fenix 8 Pro or fenix E) can be added in `manifest.xml`, or through the VS Code command *Monkey C: Edit Products*.

## Building

1. Install the [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/) and download the latest SDK plus the fenix 8 device files.
2. Install Visual Studio Code and the **Monkey C** extension by Garmin.
3. Run *Monkey C: Generate a Developer Key* (once only).
4. Open this folder in VS Code and press **F5** to run it in the simulator, choosing your fenix 8 model.

## Installing on your watch

1. In VS Code run *Monkey C: Build for Device* and pick your fenix 8 model. This creates a `.prg` file.
2. Connect the watch to your computer by USB.
3. Copy the `.prg` file into the `GARMIN/APPS` folder on the watch.
4. Disconnect, then on the watch go to **Watch Face** and select **Transformation**.

## Project layout

```
manifest.xml                    App ID, type and supported devices
monkey.jungle                   Build configuration
source/TransformationApp.mc     App entry point
source/TransformationView.mc    All drawing logic
resources/                      Strings, settings, launcher icon
```
