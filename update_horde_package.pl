#!/usr/bin/perl
# -------------------------------------------------------------------
# Loading script requirments
use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use IO::File;
use XML::Simple;
use POSIX qw(strftime locale_h);

# Perl's differenciation between string and numeric comparisons
# is something I'll never get. It's annoying, at best.
# So don't bother me!
no warnings 'numeric';

# Force standard locale to avoid localized Month names, etc.
setlocale(LC_CTYPE, "C");

# IMPORTANT
# Usually the following modules are to be installed separatelly
# through CPAN or your OS's package management.
use WWW::Mechanize;
use Config::IniFiles;
use Mail::Address;
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
my $beta;
my $target_version;
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
   'beta'               => \$beta,
   'target_version:s'   => \$target_version,
   'no_commit'          => \$no_commit,
   'dsc_file'           => \$dsc_file
);

# Fill the gaps with default values or try to be smart
$feed_url         = "http://pear.horde.org/feed.xml"                    unless ($feed_url);
$path_to_package  = '.'                                                 unless ($path_to_package);
$beta             = 0                                                   unless ($beta);
$comment          = 'Automated package update.'                         unless ($comment);
$maintainer_name  = determine_maintainer('name', 1)                     unless ($maintainer_name);
$maintainer_email = determine_maintainer('email', 1)                    unless ($maintainer_email);
$spec_file        = find_special_file({type => 'spec'})                 unless ($spec_file);
$change_file      = find_special_file({type => 'change'})               unless ($change_file);
$target_version   = 'latest'                                            unless ($target_version);
$basename         = determine_basename()                                unless ($basename);
$no_commit        = 0                                                   unless ($no_commit);
$dsc_file         = find_special_file({type => 'dsc', nonleathal => 1}) unless ($dsc_file);

# If debug mode is on, print the values
dbg_show_args();

# -------------------------------------------------------------------
# Run
process({
   feed_data => download_feed({ raw => 0, xml => 1, url => $feed_url })
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
   my @config_address = Mail::Address->parse($config->{$api_url}->{email});

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
sub download_feed {

   my $param = shift;

   my $raw = $param->{raw} || 0;
   my $xml = $param->{xml} || 1;
   my $url = $param->{url} || $feed_url;

   my $xmlproc = new XML::Simple;
   my $netmech = WWW::Mechanize->new();

   $netmech->get($url);

   return $xmlproc->XMLin($netmech->content()) if ($xml || (!$raw && !$xml));
   return $netmech->content() if ($raw);
}

# -------------------------------------------------------------------
sub process {

   my $param = shift;
   my $feed_data = $param->{feed_data} || die "No feed data provided.\n";

   # ---------------------------------------------
   # Filter relevant entries from the feed
   my $versions_available = [];

   foreach my $i (keys($feed_data->{entry})) {
      my $entry = $feed_data->{entry}->{$i};
      my $search_basename = $basename . ' ';
      next unless ($entry->{title} =~ /^$search_basename/);

      my $pkg_name = $basename;

      # beta or stable?
      my $status = $entry->{title};
      $status =~ s/$basename//g;
      $status =~ s/.*\(//g;
      $status =~ s/\)//g;
      $status =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;

      # Filter betas unless wanted
      next if (!$beta && ($status eq 'alpha' || $status eq 'beta' || $status eq 'RC'));

      # Separate the version number
      my $version = $entry->{title};
      $version =~ s/$basename//g;
      $version =~ s/\(.*\)//g;
      $version =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;

      # Attach those new data to the entries existing data
      $entry->{pkg_name} = $pkg_name;
      $entry->{status} = $status;
      $entry->{version} = normalize_version($version);

      push(@$versions_available, $entry);
   }

   # ---------------------------------------------
   # Sort entries by versions
   @$versions_available = sort compare_version @$versions_available;

   # Find the current version within all versions available
   my $current_version_index = find_version({
      versions_available => $versions_available,
      target_version => determine_current_version({ raw => 1 }),
      die_if_no_match => 1
   });


   my $target_version_index;

   # Process "latest" package
   if ($target_version eq 'latest') {
      $target_version_index = scalar(@$versions_available) - 1;
   } elsif ($target_version eq 'next') {
      $target_version_index = $current_version_index + 1;
   } else {
      $target_version_index = find_version({
         versions_available => $versions_available,
         target_version => $target_version,
         die_if_no_match => 1
      });
   }

   # Abort exection if target versions equals current version
   if ($current_version_index == $target_version_index) {
      die "Target version equals current version. Nothing to do here :)\n";
   }

   # Prepare the changelog for this update.
   my $changelog = compile_changelog({
      stop => $current_version_index,
      start => $target_version_index,
      versions_available => $versions_available
   });

   # Download the new file
   download_file({
      url => $versions_available->[$target_version_index]->{link}->{href}
   });

   # Update the changes file
   update_changes_file({
      file => $change_file,
      changelog => $changelog,
      maintainer_name => $maintainer_name,
      maintainer_email => $maintainer_email,
      new_version => $versions_available->[$target_version_index]->{version}->{string}
   });

   # Update the spec file
   update_spec_file({
      file => $spec_file,
      new_version => $versions_available->[$target_version_index]->{version}->{string}
   });

   # Update an optional description file
   update_dsc_file({
      file => $dsc_file,
      version => $versions_available->[$target_version_index]->{version}->{string},
      maintainer_name => $maintainer_name,
      maintainer_email => $maintainer_email
   });

   # Delete the old tarball
   delete_version_tarball({
      version_entry => $versions_available->[$current_version_index]
   });

   # Do the commit unless --no_commit is set
   publish_to_obs() unless($no_commit);

}

# -------------------------------------------------------------------
sub delete_version_tarball {

   my $param = shift;

   my $version_entry = $param->{version_entry} || die "Please specify a version.\n";

   # Determine Filename
   my $download_url = $version_entry->{link}->{href};
   my $filename = substr($download_url, rindex($download_url, '/'));

   my $file_path = $path_to_package . "/" . $filename;

   die "File doesn't exist or isn't writable: " . $file_path unless (-e $file_path && -w $file_path) . "\n";
   unlink($file_path);

   return 0;
}

# -------------------------------------------------------------------
sub publish_to_obs {

   my $api_url = get_obs_api();

   my $ci_command = sprintf("osc ar ; osc -A %s ci -m %s", $api_url, $comment);
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

   my $versions_available = $param->{versions_available} || die "Please provide an array of versions.\n";
   my $start = $param->{start} || die "Please provide an index for the start version;\n";
   my $stop = $param->{stop} || die "Please provide an index for the stop version;\n";

   for (my $i = $start; $i > $stop; $i--) {
      my @lines = split(/\n/, $versions_available->[$i]->{content});
      my $new_version = $versions_available->[$i]->{version}->{string};

      $changelog .= sprintf(
         "-------------------------------------------------------------------\n%s - %s <%s>\n\n- Version %s\n",
         strftime("%a %b %e %H:%M:%S UTC %Y", gmtime()),
         $maintainer_name,
         $maintainer_email,
         $new_version
      );

      foreach my $line (@lines) {
         next unless ($line =~ /^\*\s\[.*\]/ || $line =~ /^\ *\s\[.*\]/);
         $line = XML::Entities::decode('all', $line);
         $line =~ s/^\*/\-/g;
         $changelog .= $line . "\n";
      }

      $changelog .= "\n";
   }

   return $changelog;
}

# -------------------------------------------------------------------
# Finds a specified version within an array of versions, returning
# the index. If no match is found, return -1 or die on request.
sub find_version {

   my $param = shift;
   my $index = -1;

   my $versions_available = $param->{versions_available} || die "Please provide an array of versions.\n";
   my $target_version = $param->{target_version} || die "Please provide a target version.\n";
   my $die_if_no_match = $param->{die_if_no_match} || 0;

   die "Expecting an Array reference." unless (ref($versions_available) eq 'ARRAY');
   $target_version = $target_version->{string} if (ref($target_version) eq 'HASH');

   for (my $i = 0; $i < scalar(@$versions_available) ; $i++) {
      next unless ($versions_available->[$i]->{version}->{string} eq $target_version);
      $index = $i;
      last;
   }

   die "No results found while searching for Version " . $target_version . "\n" if ($index == -1 && $die_if_no_match);

   return $index;
}

# -------------------------------------------------------------------
sub compare_version {

   my $av = $a->{version};
   my $bv = $b->{version};

   ### DEV VERSIONS

   # ---------------------------------
   # Minor Dev Versiopns
   if ($av->{dev} ne '' && $av->{minor} == $bv->{minor}) {

      # Compare dev states (alpha, beta, RC)
      if ($bv->{dev} ne '' && $av->{dev} ne $bv->{dev}) {
         return 1 if (($av->{dev} eq 'beta' || $av->{dev} eq 'beta') && $bv->{dev} eq 'alpha');
         return -1 if ($av->{dev} eq 'alpha' && ($bv->{dev} eq 'beta' || $bv->{dev} eq 'beta'));
      }

      # Compare releases
      if ($av->{dev} eq $bv->{dev}) {
         return 1 if ($av->{release} > $bv->{release});
         return -1 if ($av->{release} < $bv->{release});
      }

   }

   # ---------------------------------
   # Major Dev Versiopns
   if ($av->{dev} ne '' && $av->{major} == $bv->{major}) {

      # Compare dev states (alpha, beta, RC)
      if ($bv->{dev} ne '' && $av->{dev} ne $bv->{dev}) {
         return 1 if (($av->{dev} eq 'beta' || $av->{dev} eq 'beta') && $bv->{dev} eq 'alpha');
         return -1 if ($av->{dev} eq 'alpha' && ($bv->{dev} eq 'beta' || $bv->{dev} eq 'beta'));
      }

      # Compare releases
      if ($av->{dev} eq $bv->{dev}) {
         return 1 if ($av->{release} > $bv->{release});
         return -1 if ($av->{release} < $bv->{release});
      }

   }

   # ---------------------------------
   # Master Dev versions
   if ($av->{dev} ne '' && $av->{master} == $bv->{master}) {

      # Compare dev states (alpha, beta, RC)
      if ($bv->{dev} ne '' && $av->{dev} ne $bv->{dev}) {
         return 1 if (($av->{dev} eq 'beta' || $av->{dev} eq 'beta') && $bv->{dev} eq 'alpha');
         return -1 if ($av->{dev} eq 'alpha' && ($bv->{dev} eq 'beta' || $bv->{dev} eq 'beta'));
      }

      # Compare releases
      if ($av->{dev} eq $bv->{dev}) {
         return 1 if ($av->{release} > $bv->{release});
         return -1 if ($av->{release} < $bv->{release});
      }

   }

   # ---------------------------------
   ### STABLE VERSIONS

   # Master Stable
   # version numbers are not necessarily numeric.
   # They can contain characters in any place and should be compared as strings
   return 1 if ($av->{master} gt $bv->{master});
   return -1 if ($av->{master} lt $bv->{master});
   ## FIXME: what do we do ith both are equal? Return 0?

   # Major Stable
   return 1 if ($av->{major} gt $bv->{major});
   return -1 if ($av->{major} lt $bv->{major});
   ## FIXME: what do we do ith both are equal? Return 0?

   # Minor Stable
   return 1 if ($av->{minor} gt $bv->{minor});
   return -1 if ($av->{minor} lt $bv->{minor});
   ## FIXME: what do we do ith both are equal? Return 0?

}

# -------------------------------------------------------------------
sub normalize_version {

   my $version = shift;

   my $retval = {
      string => $version,
      master => '',
      major => '',
      minor => '',
      dev => '',
      release => ''
   };


   # Determine development status
   my $dev;
   $dev = 'alpha' if ($version =~ /alpha/);
   $dev = 'beta' if ($version =~ /beta/);
   $dev = 'RC' if ($version =~ /RC/);
   $retval->{dev} = $dev if ($dev);

   # Determine development release
   if ($dev) {
      my $release = $version;
      $release =~ s/^.*(?:alpha|beta|RC)//g;
      $retval->{release} = $release;
   }

   # Cut Dev stuff away from the version string
   $version =~ s/(?:alpha|beta|RC).*$//g;
   my @parts = split(/\./, $version);
   $retval->{master} = $parts[0];
   $retval->{major} = $parts[1];
   $retval->{minor} = $parts[2];

   return $retval;

}

# -------------------------------------------------------------------
sub determine_current_version {

   my $param = shift;

   my $raw = $param->{raw} || 1;
   my $normalize = $param->{normalize} || 0;

   my $current_version;

   # Read it from the spec file
   my $spec_fh = IO::File->new($spec_file, 'r');
   my @lines = <$spec_fh>;
   $spec_fh->close();

   foreach my $line (@lines) {
      next unless ($line =~ /^Version\:/);
      $line =~ s/^Version\://g;
      $line =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
      $current_version = $line;
      last;
   }

   return normalize_version($current_version) if ($normalize);
   return $current_version;
}

# -------------------------------------------------------------------
exit 0;
