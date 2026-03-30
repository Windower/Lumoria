<div id="content-root"></div>
<h1 align="center">
      <img align="center" src="data/icons/hicolor/scalable/apps/net.windower.Lumoria.svg" alt="Lumoria" width="175">
    <br><br>
    Lumoria
</h1>

<p align="center">
  <strong>A native Linux launcher and installer for Final Fantasy XI.</strong>
</p>

## What is this?

Getting FFXI running on Linux has always meant juggling Lutris, ProtonUp-Qt, Winetricks, and whatever else breaks this week. Lumoria rolls all of that into a single app.

Still rough around the edges, but it:
- Manages Wine prefixes -- create, configure, launch.
- Downloads and swaps Wine builds (Kron4ek Staging, GE-Proton, Proton-CachyOS).
- Installs and toggles DXVK.
- Installs the FFXI retail client and everything it needs to run under Wine.
- Supports Windower 4.
- Patches PlayOnline with the Large Address Aware flag -- no external tools needed.

## Quick start

### Installing using Flatpak

While the eventual goal is to get on Flathub, we want to work out the rough edges before submission. The testing repository can be installed using the below commands.

***Note***: You need to have [Flathub](https://flathub.org/en/setup) installed on your device first.

#### Verifying releases

Flatpak releases are signed with GPG. The public key is bundled in the `.flatpakrepo` file.

Fingerprint: `75DC 1210 5CCA A971 94A6 7D07 9FE9 2A31 9A93 0950`

```sh
flatpak remote-add --if-not-exists --user lumoria https://lumoria.windower.net/repo/lumoria.flatpakrepo
flatpak install --user -y lumoria net.windower.Lumoria
```

### Building from source

See [BUILD.md](BUILD.md) for full build instructions, release workflow, and environment variable reference.

## Policy on Cheating, Exploits, Botting, and Third Party Tools

Stahp. While it might be possible to run cheats or hacks via Lumoria, we don't endorse or support it. Issues or discussions about getting them running will be closed immediately with no explanation. In time, we might support a small selection of useful and community acceptable tools. This will be at our discretion and will be evaluated on a case by case situation.

## License

GPL-3.0-or-later. See the [LICENSE](LICENSE) file for details.

## Disclaimer

All trademarks or registered trademarks are the property of their respective owners.

**(c) 2002-2012 SQUARE ENIX CO., LTD. All Rights Reserved. Title Design by Yoshitaka Amano. FINAL FANTASY and VANA'DIEL are registered trademarks of Square Enix Co., Ltd. SQUARE ENIX, PLAYONLINE and the PlayOnline logo are trademarks of Square Enix Co., Ltd.**

We are not affiliated with SQUARE ENIX CO., LTD. in any way.

