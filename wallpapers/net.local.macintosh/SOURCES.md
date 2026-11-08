# Sources

The Macintosh wallpaper recreates the animated "Macintosh" wallpaper and screen saver that Apple added in
macOS Sequoia for the Macintosh's 40th anniversary.

| What | Where it came from |
|---|---|
| Pixel artwork (`contents/images/`) | Susan Kare's original Macintosh icons and screens, as redrawn by Apple for macOS Sequoia (`/System/Library/ExtensionKit/Extensions/WallpaperMacintoshExtension.appex`). Downloaded from Stephen Hackett's archive: [MacintoshImages.zip](https://media.512pixels.net/wp-content/uploads/2025/06/MacintoshImages.zip) |
| Scene scripts (`contents/programs/apple/`) | Apple's `.program` files from the same extension, published as plain text by Stephen Hackett: [IconGarden](https://media.512pixels.net/wp-content/uploads/2025/06/IconGarden.txt), [System6ControlPanel](https://media.512pixels.net/wp-content/uploads/2025/06/System6ControlPanel.txt) |
| How the wallpaper works | Stephen Hackett, [Inside the Macintosh Screen Saver](https://512pixels.net/2025/06/inside-macintosh-screen-saver/) (512 Pixels, June 2025) and [macOS Sequoia's Macintosh wallpapers](https://512pixels.net/2024/06/macos-sequoias-macintosh-wallpapers) |
| Colours | Sampled from Apple's rendered stills ([Basic Apple Guy](https://basicappleguy.com/haberdashery/macintoshwallpapers)) |
| Background | [AppleInsider: Apple honors Susan Kare in the macOS Sequoia wallpaper](https://appleinsider.com/articles/24/06/12/apple-honors-original-icon-designer-susan-kare-in-macos-sequoia-wallpaper) |

The artwork and the two scripts in `programs/apple/` are © Apple Inc. They are included here, unmodified, so the
wallpaper works out of the box, with credit to Apple, Susan Kare and Stephen Hackett. Fenwyre is not affiliated
with or endorsed by Apple. If you are a rights holder and want them removed, open an issue.

Everything else here (the `.program` interpreter `Machine.js`, the renderer, the shaders and the scenes in
`programs/authored/`) is original to this project.
