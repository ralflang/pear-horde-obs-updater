package Util;
use strict;
use File::Basename;
use XML::Simple;
use WWW::Mechanize;
use Data::Dumper;
use File::Slurp;
# -------------------------------------------------------------------
sub download_feed {

  my $param = shift;
  my $content;
  my $cachefile = dirname($0) . "/feed.xml";
  if (-r $cachefile) {
    $content = read_file( $cachefile );
  } else {
    my $netmech = WWW::Mechanize->new();
    $netmech->get($param->{url});
    $content = $netmech->content();
    open (my $cache, '>', $cachefile);
    print $cache $content;
    close $cache; 
  }
  my $xmlproc = new XML::Simple;
  return $xmlproc->XMLin($content);
}


## Return a list of releases
## Params:
##  $feed hashref of the feed
##  $basename Releases of which package? If empty, get all releases of all packages
## returns arrayref of hashref

sub get_releases {
  my $feed = shift;
  my $basename = shift || '';
  my @releases;
  foreach my $url (keys %{$feed->{entry}}) {
    next if $basename && $url !~ /$basename-/;
    push  @releases, Util::release_to_version_hash($url);
  }
  return \@releases;
}

sub filter_releases {
  my $releases = shift;
  my $filter = shift || { stable => 1, rc => 0, beta => 0, alpha => 0, major => 0, minor => 0, patch => 0, pkg => '' };
  my @legit;
  foreach my $pkg (@$releases) {
    ## filters
    next if ($filter->{pkg} && $pkg->{pkg} ne $filter->{pkg});
    next if ($pkg->{dev} =~ /RC/ && $filter->{'rc'} == 0);
    next if ($pkg->{dev} =~ /alpha/ && $filter->{'rc'} == 0);
    next if ($pkg->{dev} =~ /beta/ && $filter->{'rc'} == 0);
    next if ($filter->{major} && $filter->{major} != $pkg->{major});
    next if ($filter->{minor} && $filter->{minor} != $pkg->{minor});
    next if ($filter->{patch} && $filter->{minor} != $pkg->{patch});

    push @legit, $pkg;
  }
  return \@legit;
}


## Return the best release identifier string or null
## This is generally the highest version which fits criteria.
## params:
## $releases ArrayRef of Release URL Strings
## filter: A HashRef of options: {stable => 1, rc => 0, beta => 0, alpha => 0 }
sub get_best_release {
  my $releases = shift;
  my $filter = shift || { stable => 1, rc => 0, beta => 0, alpha => 0, major => 0, minor => 0, patch => 0, pkg => '' };
  my @legit = Util::filter_releases($releases, $filter);
  die "No apropiate version found" unless @legit;
  return pop @{Util::sort_releases(@legit)};
  
}

# params:
## $releases ArrayRef of release hashrefs

sub sort_releases {
  my $releases = shift;
  return [sort Util::compare_versions @$releases];
}

## Return a version hash for comparison
## Params: 
## $release STRING a release string

sub release_to_version_hash {
    my $release = shift;
    my ($package, $major, $minor, $patch, $dev) = $release =~ /\/(\w+)-(\d+)\.(\d+)\.(\d+)(\w*)/;
    return { major => $major, 
             minor => $minor, 
             patch => $patch, 
             dev => $dev, 
             pkg => $package, 
             url => $release, 
             string => sprintf("%d.%d.%d%s", $major, $minor, $patch, $dev) 
             };
}

## A compare function callback for version hashes, suitable for sort
## returns -1, 0 or 1
sub compare_versions {
   return  ($a->{major} <=> $b->{major} 
        or $a->{minor} <=> $b->{minor} 
        or $a->{patch} <=> $b->{patch}
        ## 
        or ( !$a->{dev} && $b->{dev} ? 1 : 0 )
        or ( !$b->{dev} && $a->{dev} ? -1 : 0 )
        or lc($a->{dev})   cmp lc($b->{dev}))
}

sub get_specfile_version {
   my $params = shift || {};
   my $specfile_name = defined ($params->{specfilename}) ? $params->{specfilename} : shift @{glob '*.spec'};
   my $version = '';
#    # Read it from the spec file
   my $spec_fh = IO::File->new($specfile_name, 'r');
   foreach my $line (<$spec_fh>) {
     last if ($version) = $line =~ /^\s*Version:\s*([\w\.]*)[\s#]*/;
   }
   $spec_fh->close();
   return $version;
}


## parse full and partial version strings
sub version_string_to_version_hash {
  my $version_string = shift;
  my $major = ($version_string =~ s/^(\d+)\.*//) ? $1 : '';
  my $minor = ($version_string =~ s/^(\d+)\.*//) ? $1 : '';
  my $patch = ($version_string =~ s/^(\d+)\.*//) ? $1 : '';
  my $dev   = $version_string || '';
  my $hash = { major => $major, 
           minor => $minor, 
           patch => $patch, 
           dev => $dev
         };
  $hash->{string} = sprintf('%d.%d.%d%s', $major, $minor, $patch, $dev) if (length($major) && length($minor) && length($patch));
  return $hash;
}

## parse the changelog from the <content> tags of the feed <entry> section
sub feed_get_changelog_by_version {
  my $feed = shift;
  my $version = shift;
  return {'version' => $version->{'string'}, 'changes' => $feed->{'entry'}->{$version->{'url'}}->{content} };
}

sub meta_add_changelog {

}

sub rpm_changes_add_changelog {

}

sub debian_add_changelog {

}

1;