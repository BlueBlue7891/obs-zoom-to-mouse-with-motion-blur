# OBS Zoom to Mouse with Motion Blur

An enhanced OBS Lua script that zooms a display-capture source to focus on the mouse cursor — now with configurable motion blur for smooth, cinematic transitions.

## 🚀 Features

- **Zoom to Mouse**: Automatically zooms your display capture source to focus on the mouse cursor
- **Motion Blur Control**: Adds configurable motion blur during zoom and pan movements
- **Directional Blur**: Motion blur direction matches the movement vector (NEW!)
- **Hotkey Support**: Toggle zoom and follow with customizable hotkeys
- **Smooth Animations**: Customizable zoom speed and follow sensitivity
- **Flexible Setup**: Works with various display capture sources

## 📋 Requirements

- OBS Studio 28.0 or higher
- Lua scripting support enabled (default)
- A display capture source to apply zoom to

## 🛠️ Installation

1. Download the `obs-zoom-to-mouse-motion-blur.lua` script file
2. Place it in your OBS scripts folder:
   - Windows: `%APPDATA%\obs-studio\scripts`
   - macOS: `~/Library/Application Support/obs-studio/scripts`
   - Linux: `~/.config/obs-studio/scripts`
3. Restart OBS Studio
4. Go to Tools → Scripts and add the script
5. Configure your source and settings in the script properties

## ⚙️ Configuration

### Basic Settings
- **Zoom Source**: Select the display capture source to zoom
- **Zoom Factor**: How much to zoom in (e.g., 2 = 2x zoom)
- **Zoom Speed**: How quickly the zoom animation occurs
- **Auto follow mouse**: Whether to automatically follow mouse after zooming in

### Follow Settings
- **Follow Speed**: How quickly the zoom follows the mouse
- **Follow Border**: Percentage of zoom window edge that triggers following
- **Lock Sensitivity**: When to lock zoom center (when auto-lock is enabled)
- **Follow outside bounds**: Whether to follow when mouse is outside source bounds

### Motion Blur Settings
- **Enable Motion Blur**: Toggle motion blur control
- **Blur Filter Name**: Name of the blur filter on your source (e.g., "Motion Blur")
- **Blur Parameter Name**: Parameter to control (e.g., "Size", "radius", "kawase_passes")
- **Blur Strength**: Multiplier for motion blur intensity
- **Enable Directional Blur**: Apply blur direction matching movement vector (requires compatible blur filter)

## 🔧 Setup Motion Blur

To use motion blur functionality:

1. **Install Composite Blur Plugin**:
   - Download from: https://github.com/finitesingularity/obs-composite-blur/
   - Install the plugin following the instructions in the repository
   - Restart OBS Studio

2. **Add Composite Blur Filter to Your Source**:
   - Right-click your display capture source in the Sources panel
   - Select "Filters"
   - Click the "+" button and add "Composite Blur"
   - Configure the blur filter settings (see image: composite_blur_settings.png)

3. **Configure the Script**:
   - In the script settings, enable "Enable Motion Blur"
   - The script comes pre-configured with default parameters that should work with Composite Blur
   - Adjust "Blur Strength" as needed (recommended: 0.1 - 0.3, higher values may cause performance issues)
   - See image: script_settings.png for reference configuration

## 🎮 Hotkeys

- **Toggle Zoom**: Toggle zoom in/out
- **Toggle Follow**: Toggle mouse following (when zoomed in)

## 📖 How It Works

The script works by:
1. Adding a crop filter to your source to create the zoom effect
2. Dynamically adjusting the crop filter based on mouse position
3. Optionally controlling a blur filter based on movement velocity
4. Optionally applying directional blur matching movement direction

## 🔄 Updates

This script is a fork of [BlankSourceCode/obs-zoom-to-mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse) with the following enhancements:
- Added motion blur control functionality
- Added directional blur support
- Fixed `obs_property_get_group_properties` compatibility issue
- Improved zoom animation timing

## 🐛 Troubleshooting

### Common Issues:

1. **Script fails to load**: Check that you're using a compatible OBS version
2. **Blur not working**: Verify blur filter name and parameter name match exactly
3. **Zoom not following mouse**: Ensure source is in current scene and monitor info is correct
4. **Performance issues**: Reduce zoom factor or use simpler blur filters

### Debug Logging:

Enable "Enable debug logging" in script settings to see detailed logs in OBS's script console.

## 🤝 Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Original script by [BlankSourceCode](https://github.com/BlankSourceCode)
- Composite Blur plugin by [finitesingularity](https://github.com/finitesingularity/obs-composite-blur/)
- FFI mouse position code adapted from various OBS community scripts
- Motion blur concept inspired by professional video editing software



