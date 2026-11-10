# Install

Back to the [documentation index](README.md).

From a [GitHub release](https://github.com/fmartingr/wow-addon-memories/releases): unpack `Memories-addons-<version>.zip` into `Interface/AddOns` of the flavor
folder (for example `.../World of Warcraft/_forever_/Interface/AddOns`). The zip holds the 6 `Memories*` folders.

From the repository, `WOW_DIR` is the flavor folder, the one that holds `Interface/AddOns`:

```sh
make install WOW_DIR=".../World of Warcraft/_forever_"   # copy the 6 addon folders
make link WOW_DIR=".../World of Warcraft/_forever_"      # or link them, for development
```

Both replace the 6 `Memories*` folders in `Interface/AddOns`. Then start the game and enable the addons you want in the
AddOn list.
