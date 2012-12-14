# PEAR Horde OBS Package Updater

This script updates Horde packages.

## Usage

Follow the following steps:

  * Checkout your OBS package
  * Run the update script with the `--path_to_package=</my/package/>` parameter
  * The script should now do its job. If you run into trouble, check out other parameters

The following parameter is required:

  * `--path_to_package=<path>` - This parameter defines the path to your OBS package.

The follwing parameters are available for optional use:

  * `--feed_url=<url>` - By default the script checks the official Horde Update feed (http://pear.horde.org/feed.xml). This parameter allows you to use another one.
  * `--maintainer_name=<name>` - Name of the OBS package maitainer. By default this value is obtained from you `~/.oscrc` file.
  * `--maintainer_email=<address>` - Email address of the OBS package maitainer. By default this value is obtained from you `~/.oscrc` file.
  * `--basename=<name>` - Full or partial name of the Horde package you'd like to update. By default this value is obtained from the spec file.
  * `--spec_file=<path>` - Defines the location of your package's spec file. This is nesseccary if your package contains more than one spec file.
  * `--change_file=<path>` - Defines the location of your package's changes file. This is nesseccary if your package containse more than one changes file.
  * `--dsc_file=<path>` - Defines the location of your package's optional description file. This may be nesseccary if your package containse more than one changes file. Note: This is an optional file.
  * `--comment=<comment>` - Specify a comment for the update (`osc ci -m <comment>`).
  * `--beta` - Include Beta versions. By default Alpha, Beta and RC versions are excluded.
  * `--target_version=<version|next|latest>` - Specify which version you'd like to update to. This can either be a version number or the words `next` or `latest`. `next` will update your package to the next higher version. `latest`, which is the default value, will update to the latest version available.
  * `--no_commit` - Don't commit after updates have been performed.
  * `--debug` - Enables some debug messages
