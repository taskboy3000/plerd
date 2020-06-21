# When a source file has tags:
#   add a touch file to the tag DB dirs:
#   $PLERD_ROOT/db/tags/
#                       tag1/
#                            source_file_basename1.tag
#                       tag2/
#                            source_file_basename2.tag
#                            source_file_basename3.tag
#
#   These files have no content, but make it easy to add, remove posts from tags
#   and to generate tag files from this list.
#
#   STARTING NOW, tags are normalized to lower-case.  Sorry, but it's true.  Also, no spaces.
package Plerd::Tag;
use strict;
use warnings;

use File::Basename;
use Moo;
use URI;

#-------------------------
# Attributes and Builders
#-------------------------
has 'db_directory' => (is => 'ro'); # Path::Class::Dir

has 'name' => (
    is => 'rw',
    coerce => \&_canonicalize_tag
);

has 'posts' => (
    is => 'ro',
    default => sub { [] },
);

has 'uri' => (
    is => 'ro',
    lazy => 1,
);
sub _build_uri {
    my $self = shift;

    return URI->new_abs(
        'tags/' . $self->name . '.html',
        $self->plerd->base_uri,
    );
}

#------------------
# "Public" Methods
#------------------
sub get_dir_for_tag {
    my ($self, $tag, $createDir) = @_;
    die("assert - no db") if !$self->db_directory;

    $createDir //= 0;

    my $baseDir = $self->db_directory;
    my $dir;
    if (ref $tag eq __PACKAGE__) {
        $dir = Path::Class::Dir->new($baseDir, $tag->name);
    } else {
        $dir = Path::Class::Dir->new($baseDir, $tag);
    }

    if ($createDir && !-d $dir) {
        $dir->mkpath(undef, 0755);
    }

    return $dir;
} 

sub get_tag_entry_file_for_source {
    my ($self, $tag, $source_file, $opt_create_dir) = @_;
    die("assert") if !ref $tag && !$source_file;

    my $tagDir = $self->get_dir_for_tag($tag, $opt_create_dir);
    my $sourceFileTag = $source_file->basename . ".tag";

    return Path::Class::File->new($tagDir, $sourceFileTag);
}

sub add_source_to_db {
    my ($self, $tag, $source_file) = @_;

    return if !$tag || !$source_file;
    die("assert - no db") if !$self->db_directory;

    # Pass in a string and I will make a new tag object which normalizes the name
    if (!ref $tag) {
        $tag = Plerd::Tag->new(name => $tag, db_directory => $self->db_directory);
    }

    my $entry = $self->get_tag_entry_file_for_source($tag, $source_file, 1);    

    if (!-e $entry) {
        $entry->spew($source_file);
    }

    return 1;
}

sub tag_has_source {
    my ($self, $tag, $source_file) = @_;
    return if !$tag || !$source_file;

    # Pass in a string and I will make a new tag object which normalizes the name
    if (!ref $tag) {
        $tag = Plerd::Tag->new(name => $tag, db_directory => $self->db_directory);
    }

    my $tagDir = $self->get_dir_for_tag($tag);
    if (!-d $tagDir) {
        return; # no such tag
    }

    my $entry = $self->get_tag_entry_file_for_source($tag, $source_file);    
    return (-e $entry);
}

sub remove_source_from_db {
    my ($self, $tag, $source_file) = @_;

    return if !$tag || !$source_file;

    # Pass in a string and I will make a new tag object which normalizes the name
    if (!ref $tag) {
        $tag = Plerd::Tag->new(name => $tag, db_directory => $self->db_directory);
    }

    my $entry = $self->get_tag_entry_file_for_source($tag, $source_file);    

    if (-e $entry) {
        $entry->remove;
    }

    return 1;
}

# Return an array ref of Path::Class::File objects
# that are the paths to the source files that generated
# these tags.
#
# Source files can easily be converted to Posts, which
# can emit publication URIs
sub get_sources_by_tag {
    my ($self, $tag, $opt_source_dir) = @_;

    return if !$tag;

    my $tagDir = $self->get_dir_for_tag($tag);
    if (!-d $tagDir) {
        return [];
    }

    my @sources;
    for my $entry ($tagDir->children) {
        if ($entry =~ /.tag$/) {
            if ($opt_source_dir) {
                push @sources,
                    Path::Class::File->new($opt_source_dir, basename($entry->basename, ".tag"));
            } else {
                my $fh = $entry->openr || die("assert");
                my $line = readline($fh);
                close($fh);
                chomp($line);
                push @sources, Path::Class::File->new($line);
            }
        }
    }

    return \@sources;
}

sub remove_tag_from_db {
    my ($self, $tag) = @_;
    my $tagDir = $self->get_dir_for_tag($self->name);

    if (-d $tagDir) {
        $tagDir->rmtree;
    }

    return 1;
}

# @todo: remove me
sub add_post {
    my ($self, $post) = @_;

    my $added = 0;
    if ( @{$self->posts} ) {
        for (my $index = 0; $index <= @{$self->posts} - 1; $index++ ) {
            if ( $self->posts->[$index]->date < $post->date ) {
                splice @{$self->posts}, $index, 0, $post;
                $added = 1;
                last;
            }
        }
    }

    unless ($added) {
        push @{$self->posts}, $post;
    }
}


#-------------------
# "Private" Methods
#-------------------
sub _canonicalize_tag {
    my ($tag) = @_;

    chomp($tag);

    # no html
    if ($tag =~ /[<>]/) {
        $tag =~ s{(</?[^>]+>)}{}g;
    }

    # no spaces
    $tag =~ s/\s+/_/g;

    return $tag;
}
1;

