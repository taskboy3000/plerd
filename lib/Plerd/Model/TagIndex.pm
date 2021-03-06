# Joe Johnston <jjohn@taskboy.com>
package Plerd::Model::TagIndex;
use Modern::Perl '2018';

use Fcntl       ( ':flock' );
use Digest::SHA ( 'sha1_hex' );
use Path::Class::File;
use Moo;
use URI;

use Plerd::Config;
use Plerd::Remembrancer;

#-------------------------
# Attributes and Builders
#-------------------------
has 'config' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_config'
);

sub _build_config {
    Plerd::Config->new();
}

has 'publication_file' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_publication_file'
);

sub _build_publication_file {
    my ( $self ) = @_;

    Path::Class::File->new( $self->config->publication_directory,
        "tags.html" );
}

has 'template_file' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_template_file'
);

sub _build_template_file {
    my ( $self ) = @_;
    Path::Class::File->new( $self->config->template_directory, "tags.tt" );
}

has 'uri' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_uri'
);

sub _build_uri {
    my ( $self ) = @_;
    my $base_uri = $self->config->base_uri;
    return URI->new_abs( $self->publication_file->basename, $base_uri );
}

#-------------------
# Public Methods
#-------------------
sub out_of_date {
    my ( $self ) = @_;
    if ( !-e $self->publication_file ) {
        return 1;
    }

    my $pub_date = $self->publication_file->stat->mtime;
    my ( $latest_key ) = @{ $self->config->tag_memory->latest_keys };

    if ( !$latest_key ) {
        return 1;
    }

    my $last_key_date = $self->config->tag_memory->updated_at( $latest_key );
    return $last_key_date > $pub_date;
}

# Return
#   {
#      'A' => {
#              'a_tag1' => [
#                             { uri => URI_Object, title => '...'}, ...
#                          ],
#              'a_tag2' => [ {...}, {...} ],
#             },
#             ...
#    }
sub get_tag_links {
    my ( $self ) = @_;
    my $tm = $self->config->tag_memory;
    my %found;

    for my $key ( @{ $tm->keys } ) {
        my $first_letter = uc( substr( $key->[ 0 ], 0, 1 ) );
        my $key_struct   = $tm->load( $key ) || next;

        for my $rec ( @$key_struct ) {
            my $tag = $key->[ 0 ];
            push @{ $found{ $first_letter }->{ $tag } },
                {
                uri   => URI->new( $rec->{ uri } ),
                title => $rec->{ title }
                };
        }
    }

    return \%found;
}

# Creating:
#   tag1 => [
#               { source_file => $src, title => $title, uri => $uri }
#           ]
sub update_tag_for_post {
    my ( $self, $tag, $post ) = @_;
    return if !ref $tag && !ref $post;

    my $tm     = $self->config->tag_memory;
    my $lock   = $self->get_lock( $tag );
    my $memory = $tm->load( $tag->name );

    my $changed = 0;
    if ( ref $memory ) {

        # Does this memory have this post?
        my $found = 0;
        for my $rec ( @$memory ) {
            if ( $rec->{ source_file } eq $post->source_file->stringify ) {

                # updating existing record
                for my $property ( 'uri', 'title' ) {
                    if ( !exists $rec->{ $property } ) {
                        $rec->{ $property } = $post->$property() . "";
                        $changed = 1;
                    } elsif ( $rec->{ $property } ne $post->$property ) {
                        $changed = 1;
                        $rec->{ $property } = $post->$property() . "";
                    }
                }

                $found = 1;
                last;
            }
        }

        if ( !$found ) {

            # appending to existing list
            push @$memory,
                {
                source_file => $post->source_file->absolute->stringify,
                uri         => $post->uri->as_string,
                title       => $post->title,
                };
            $changed = 1;
        }

    } else {

        # creating a new record
        $memory = [
            {   source_file => $post->source_file->absolute->stringify,
                uri         => $post->uri->as_string,
                title       => $post->title,
            }
        ];
        $changed = 1;

    }

    if ( $changed ) {
        $tm->save( $tag->name, $memory );
    }

    $self->free_lock( $lock => $tag );
    return 1;
}

sub remove_tag_from_post {
    my ( $self, $tag, $post ) = @_;
    return if !$tag;

    my $src_file;
    if (   ref $post eq 'Plerd::Model::Post'
        || ref $post eq 'Plerd::Mode::Note' )
    {
        $src_file = $post->source_file->stringify;
    } else {
        $src_file = $post;
    }

    my $tag_name = ref $tag ? $tag->name : $tag;
    my $tm       = $self->config->tag_memory;
    my $lock     = $self->get_lock( $tag );
    my $memory   = $tm->load( $tag_name );

    my $changed = 0;

    if ( ref $memory ) {

        # Does this memory have this post?
        my @tmp;
        for my $rec ( @$memory ) {
            if ( $rec->{ source_file } eq $src_file ) {
                $changed = 1;
            } else {
                push @tmp, $rec;
            }
        }

        if ( $changed ) {
            if ( @tmp ) {
                $tm->save( $tag_name, \@tmp );
            } else {

                # No further references to this tag
                $tm->remove( $tag->name );
            }
        }
    }
    $self->free_lock( $lock => $tag );
    return 1;
}

sub get_lock_filename_for_tag {
    my ( $self, $tag ) = @_;

    my $sha = sha1_hex( $tag->name );

    my $lockFileName = $self->config->run_directory . '/tag-$sha.lock';
    return $lockFileName;
}

sub get_lock {
    my ( $self, $tag ) = @_;
    my $lockFileName = $self->get_lock_filename_for_tag( $tag );
    open my $lockFH, '>', $lockFileName or die "lock file: $!";
    flock $lockFH, LOCK_EX;
    return $lockFH;
}

sub free_lock {
    my ( $self, $lockFH, $tag ) = @_;
    my $lockFileName = $self->get_lock_filename_for_tag( $tag );
    flock( $lockFH, LOCK_UN );
    unlink $lockFileName;
}

1;
