#!/usr/bin/perl
# -------------------------------------------------------------------
# Loading script requirments
use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use IO::File;
use XML::Simple;
use POSIX qw(strftime locale_h LC_ALL LC_CTYPE);
use File::Basename;
use lib dirname($0);
use Util;

# Perl's differenciation between string and numeric comparisons
# is something I'll never get. It's annoying, at best.
# So don't bother me!
#no warnings 'numeric';

# Force standard locale to avoid localized Month names, etc.
setlocale(LC_CTYPE, "C");
setlocale(LC_ALL, "C");

# IMPORTANT
# Usually the following modules are to be installed separatelly
# through CPAN or your OS's package management.
use WWW::Mechanize;
use Config::IniFiles;
use Email::Address;
use File::HomeDir;
use XML::Entities;

# -------------------------------------------------------------------
# Make sure error messages and such are more prominently displayed.
print "\n";

# -------------------------------------------------------------------
# Process the command line options

# Associate Perl with the variables uses
my $debug;
my $feed_url;
my $maintainer_name;
my $maintainer_email;
my $basename;
my $spec_file;
my $change_file;
my $comment;
my $path_to_package;
my $alpha;
my $beta;
my $rc;
my $target_version;
my $current_version;
my $no_commit;
my $dsc_file;

# Attemt to get arguments
GetOptions(
   'debug'              => \$debug,
   'path_to_package:s'  => \$path_to_package,
   'feed:s'             => \$feed_url,
   'maintainer_name:s'  => \$maintainer_name,
   'maintainer_email:s' => \$maintainer_email,
   'basename:s'         => \$basename,
   'spec_file:s'        => \$spec_file,
   'change_file:s'      => \$change_file,
   'comment:s'          => \$comment,
   'alpha'               => \$alpha, # allow alpha
   'beta'               => \$beta, # allow beta versions
   'rc'               => \$rc, # allow rc versions
   'current_version:s'  => \$current_version,
   'target_version:s'   => \$target_version,
   'no_commit'          => \$no_commit,
   'dsc_file'           => \$dsc_file
);

# Fill the gaps with default values or try to be smart
$feed_url         = "http://pear.horde.org/feed.xml"                    unless ($feed_url);
$path_to_package  = '.'                                                 unless ($path_to_package);
$alpha            = 0                                                   unless ($alpha);
$beta             = 0                                                   unless ($beta);
$rc               = 0                                                   unless ($rc);
$comment          = 'Automated package update.'                         unless ($comment);
$maintainer_name  = determine_maintainer('name', 1)                     unless ($maintainer_name);
$maintainer_email = determine_maintainer('email', 1)                    unless ($maintainer_email);
$spec_file        = find_special_file({type => 'spec'})                 unless ($spec_file);
$change_file      = find_special_file({type => 'change'})               unless ($change_file);
$target_version   = 'latest'                                            unless ($target_version);
$current_version  = '' unless ($current_version);
$basename         = determine_basename($spec_file)                      unless ($basename);
$no_commit        = 0                                                   unless ($no_commit);
$dsc_file         = find_special_file({type => 'dsc', nonleathal => 1}) unless ($dsc_file);

# If debug mode is on, print the values
dbg_show_args();

# -------------------------------------------------------------------
# Run

my $feed = Util::download_feed({url => $feed_url });

my $releases = Util::get_releases($feed, $basename);
## TODO: convert (partial) target version to a hash and supply it, if given.
my $legit_releases = Util::sort_releases(Util::filter_releases($releases, {alpha => $alpha, beta => $beta, rc => $rc}));

process({
   feed_data => $feed,
   target_release => $legit_releases->[-1],
   releases => $releases,
   specfilename => $spec_file
});


# -------------------------------------------------------------------
# -------------------------------------------------------------------
# -------------------------------------------------------------------
# -------------------------------------------------------------------
# -------------------------------------------------------------------
# -------------------------------------------------------------------
# If debug mode is on, print the values
sub dbg_show_args {

   return unless ($debug);

   print "\n--------------------------\nDebug Message: Input Arguments (incl. Defaults)\n\n";
   printf "  * debug            : %s\n", $debug;
   printf "  * feed_url         : %s\n", $feed_url;
   printf "  * maintainer_name  : %s\n", $maintainer_name;
   printf "  * maintainer_email : %s\n", $maintainer_email;
   printf "  * basename         : %s\n", $basename;
   printf "  * spec_file        : %s\n", $spec_file;
   printf "  * change_file      : %s\n", $change_file;
   printf "  * comment          : %s\n", $comment;
   printf "  * path_to_package  : %s\n", $path_to_package;
   printf "  * beta             : %s\n", $beta;
   printf "  * target_version   : %s\n", $target_version;
   printf "  * no_commit        : %s\n", $no_commit;
   printf "  * dsc_file         : %s\n", $dsc_file;

   return 0;
}

# -------------------------------------------------------------------
# Try to get mainatiner data
sub determine_maintainer {

   # Argument: Define the key (e.g. name, email)
   my $key = shift;

   # Argument: Set if you wish the script to end if no maintainer
   # can be determined
   my $strict = shift;

   # Default return Value
   my $retval = { name => 'unknown', email => 'unknown' };

   # Do we have an ".oscrc" file?
   my $source_path = File::HomeDir->my_home . "/.oscrc";
   my $source_found  = -e $source_path;

   my $deathmessage = "Unable to determine Maintainer. Please specify using --maintainer_name and --maintainer_email\n";


   die $deathmessage if (!$source_found && $strict);
   return $retval unless($source_found);

   my $api_url = get_obs_api();

   # Render .oscrc file
   tie my %osc_config, 'Config::IniFiles', (-file => $source_path);
   my $config = \%osc_config;
   print "\n--------------------------\nDebug Message: Contents of .oscrc (parsed)\n\n" . Dumper($config) if ($debug);

   # If no email is provided within the oscrc file, throw an error.
   die $deathmessage if (!$config->{$api_url}->{email});

   # Render the address
   my @config_address = Email::Address->parse($config->{$api_url}->{email});

   $retval->{name} = $config_address[0]->phrase;
   $retval->{email} = $config_address[0]->address;

   return $retval->{name} if ($key eq 'name');
   return $retval->{email} if ($key eq 'email');
   return $retval;

}

# -------------------------------------------------------------------
# Finds spec and changes files as required, yet throws an error if
# more than one file is found.
sub find_special_file {

   my $param = shift;
   my $type = $param->{type};
   my $nonleathal = $param->{nonleathal} || 0;

   # Read package directory contents
   opendir my($dh), $path_to_package or die "Couldn't open dir '$path_to_package': $!\n";
   my @files = readdir $dh;
   closedir $dh;

   my $special_file = '';
   my $deathmessage;
   $deathmessage = "Unable to determine Spec File. Please specify manually using --spec_file\n" if ($type eq 'spec');
   $deathmessage = "Unable to determine Changes File. Please specify manually using --change_file\n" if ($type eq 'change');
   $deathmessage = "Unable to determine Description File. Please specify manually using --dsc_file\n" if ($type eq 'dsc');

   foreach my $file (@files) {
      # If not a spec file, carry on, nothing to see here
      if ($type eq 'spec') {
         next unless ($file =~ /\.spec$/);
      } elsif ($type eq 'change') {
         next unless ($file =~ /\.changes$/);
      } elsif ($type eq 'dsc') {
         next unless ($file =~ /\.dsc$/);
      } else {
         next;
      }

      # Die if more than one spec file found
      die $deathmessage unless($special_file eq '' || $nonleathal == 1);
      $special_file = $file;
   }

   # Die in case no spec file has been found.
   die $deathmessage if($special_file eq '' && $nonleathal == 0);
   return '' if ($special_file eq '');
   return $path_to_package . '/' . $special_file;

}

# -------------------------------------------------------------------
# Try to determine the package's basename.
sub determine_basename {
   my $spec_file = shift;
   # Read the spec file
   my $spec_fh = IO::File->new($spec_file, 'r');
   my @lines = <$spec_fh>;
   $spec_fh->close();

   my $basename = '';

   # Find the right line and parse
   foreach my $line (@lines) {
      next unless ($line =~ /^%define\ prj/ || $line =~ /^%define\ pear_name/);
      chomp $line;
      $line =~ s/^%define\ prj//g;
      $line =~ s/^%define\ pear_name//g;
      $line =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
      $basename = $line;
   }

   die "Unable to determine Basename. Specify manually using --basename.\n" if ($basename eq '');

   return $basename;
}

# -------------------------------------------------------------------
sub update_dsc_file {
   my $param = shift;

   my $dsc_file = $param->{file} || $param->{dsc_file} || $dsc_file;
   return 0 if ($dsc_file eq '');

   my $version = $param->{version} || die "No version number provided.\n";
   my $maintainer_name = $param->{maintainer_name} || $maintainer_name || die "No maintainer name provided.\n";
   my $maintainer_email = $param->{maintainer_email} || $maintainer_email || die "No maintainer email provided.\n";

   # Read the .dsc file
   my $dsc_fh = IO::File->new($dsc_file, 'r');
   my @lines = <$dsc_fh>;
   $dsc_fh->close();

   my @new_lines;

   foreach my $line (@lines) {

      ## Process Version
      if ($line =~ /^Version\:/) {
         $line = sprintf("Version: %s\n", $version);
      }

      ## Process Maintainer
      if ($line =~ /^Maintainer\:/) {
         $line = sprintf("Maintainer: %s <%s>\n", $maintainer_name, $maintainer_email);
      }

      push @new_lines, $line;
   }

   $dsc_fh->open($dsc_file, 'w');
   print  $dsc_fh @new_lines;
   $dsc_fh->close();
}

# -------------------------------------------------------------------
sub process {

   my $param = shift;
   my $current_version = Util::version_string_to_version_hash(Util::get_specfile_version({specfilename => $param->{specfilename}}));
   ## Workaround until redesign
   $current_version->{pkg} = $param->{target_release}->{pkg};
   my $current_url = $param->{target_release}->{url};
   $current_url =~ s/$param->{target_release}->{string}/$current_version->{string}/;
   $current_version->{url} = $current_url;

   die "Target version equals current version. Nothing to do here :)\n" if $current_version->{string} eq $param->{target_release}->{'string'};

   # Prepare the changelog for this update.
   my $changelog = compile_changelog({
      current => $current_version,
      target => $param->{target_release},
      feed => $param->{feed_data}
   });
   
   # Download the new file
   download_file({
      url => $param->{target_release}->{url}
   });


   update_spec_file({
      file => $spec_file,
      new_version => $param->{target_release}->{string}
   });
   update_changes_file({
      new_version => $param->{target_release},
      changelog => $changelog
   });

#    # Update an optional description file
#    update_dsc_file({
#       file => $dsc_file,
#       version => $versions_available->[$target_version_index]->{version}->{string},
#       maintainer_name => $maintainer_name,
#       maintainer_email => $maintainer_email
#    });
# 
   # Delete the old tarball
   delete_version_tarball({
      version_entry => $current_version
   });
# 
#    # Do the commit unless --no_commit is set
   publish_to_obs() unless($no_commit);
# 
}

# -------------------------------------------------------------------
sub delete_version_tarball {

   my $param = shift;

   my $version_entry = $param->{version_entry} || die "Please specify a version.\n";

   # Determine Filename
   my $download_url = $version_entry->{url};
   my $filename = substr($download_url, rindex($download_url, '/'));

   my $file_path = $path_to_package . "/" . $filename;

   die "File doesn't exist or isn't writable: " . $file_path unless (-e $file_path && -w $file_path) . "\n";
   unlink($file_path);

   return 0;
}

# -------------------------------------------------------------------
# Update the file list in osc versioning, commit
sub publish_to_obs {

   my $api_url = get_obs_api();   
   chdir($path_to_package);
   my $ar_command = "osc ar";
   my $ci_command = sprintf("osc -A %s ci -m \"%s\"", $api_url, $comment);
   my $res_ar = system($ar_command);
   my $res = system($ci_command);
   warn "Something went wrong during the commit. Error Code: " . $res unless ($res == 0);
   
   return $res;
}

# -------------------------------------------------------------------
sub get_obs_api {

   my $api_source = $path_to_package . '/.osc/_apiurl';
   die "API information is missing.\n" unless (-e $api_source);

   # Get the API address
   my $api_fh = IO::File->new($api_source, 'r');
   my @api_lines = <$api_fh>;
   $api_fh->close();
   chomp $api_lines[0];
   my $api_url = $api_lines[0];

   return $api_url;
}

# -------------------------------------------------------------------
sub download_file {

   my $param = shift;

   my $url = $param->{url} || die "No URL specified.";
   my $target = $param->{target} || $path_to_package;

   my $res = system(sprintf("cd %s ; wget %s 1>/dev/null 2>&1", $target, $url));
   die sprintf("Download of URL \"%s\" was not successful. Errorcode: %s\n", $url, $res) unless ($res == 0);

   return;
}

# -------------------------------------------------------------------
sub update_changes_file {

   my $param = shift;

   my $file = $param->{file} || $change_file;
   my $changelog = $param->{changelog} || die "No Changelog provided.\n";
   my $maintainer_name = $param->{maintainer_name} || $maintainer_name || 'Maintainer';
   my $maintainer_email = $param->{maintainer_email} || $maintainer_email;
   my $new_version = $param->{new_version} || die "Please specify the new version.\n";

   # We're only interested in the version string, nothing else.
   $new_version = $new_version->{string} if (ref($new_version) eq 'HASH');

   # Make sure the file works for us
   die "Changes file $file does not seem to exist\n" unless ( -e $file );
   die "Changes file is not readable.\n" unless ( -r $file );
   die "Changes file is not writable.\n" unless ( -w $file );

   # Read the file (no write operations yet
   my $cfh = IO::File->new($file, 'r');

   my $current_changelog = '';

   foreach my $line (<$cfh>) {
      $current_changelog .= $line;
   }

   $cfh->close();

   # Preparing the new changelog content
   $changelog .= $current_changelog;

   # Reopen File for writing
   $cfh->open($file, 'w');
   print $cfh $changelog;
   $cfh->close();

   return 0;
}

# -------------------------------------------------------------------
sub update_spec_file {

   my $param = shift;

   my $file = $param->{file} || $spec_file;
   my $maintainer_name = $param->{maintainer_name} || $maintainer_name;
   my $maintainer_email = $param->{maintainer_email} || $maintainer_email;
   my $new_version = $param->{new_version} || die "Please specify the new version.\n";

   # We're only interested in the version string, nothing else.
   $new_version = $new_version->{string} if (ref($new_version) eq 'HASH');

   # Read the spec file and make the changes
   my $sfh = IO::File->new($file, 'r');
   my $content = '';
   foreach my $line (<$sfh>) {
      $line = XML::Entities::decode('all', $line);
      $line = sprintf("Version:        %s\n", $new_version) if ($line =~ /^(Version:)/);
      $content .= $line;
   }
   $sfh->close();

   # Write new spec file content to spec file
   $sfh->open($file, 'w');
   print $sfh $content;
   $sfh->close();

   return 0;

}

# -------------------------------------------------------------------
# Compiles the changelog messages of the update
sub compile_changelog {

   my $param = shift;
   my $changelog = '';
   
   my $start = $param->{current} || die "Please provide an index for the current version;\n";
   my $stop = $param->{target} || die "Please provide an index for the target version;\n";
   my $feed = $param->{feed}  || die "No feed provided for changelog\n";
   my $releases = Util::sort_releases(Util::get_releases($feed, $stop->{'pkg'}));

    $changelog .= sprintf(
        "-------------------------------------------------------------------\n%s - %s <%s>\n\n- Version %s\n\n",
        strftime("%a %b %e %H:%M:%S UTC %Y", gmtime()),
        'Ralf Lang',  #$maintainer_name,
        'lang@b1-systems.de',              # $maintainer_email,
        $stop->{string}
    );

   # filter including target but excluding current
   foreach my $release (@$releases) {
        next unless Util::compare_versions($release, $start) == 1;
        next if Util::compare_versions($release, $stop) == 1;
        my $data = $feed->{entry}->{$release->{'url'}};
        foreach my $line (split(/\n/, $data->{'content'})) {
            next if $line =~ /^$/;
            next unless ($line =~ /^\*\s\[.*\]/ || $line =~ /^\ *\s\[.*\]/);
            $line = XML::Entities::decode('all', $line);
            $line =~ s/^\*/\-/g;
            chomp ($line);
            $changelog .= $line . "\n";

        }
    }
    $changelog .= "\n";
    return $changelog;
}

exit 0;
