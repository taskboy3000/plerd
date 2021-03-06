# Joe Johnston <jjohn@taskboy.com>
package Plerd::Model::Note;
use Modern::Perl '2018';

use DateTime;
use DateTime::Format::MySQL;
use DateTime::Format::W3CDTF;
use HTML::Strip;
use Path::Class::File;
use Moo;
use MIME::Base64;
use URI;

use Plerd::Config;
use Plerd::Model::Tag;

#-------------------------
# Attributes and Builders
#-------------------------
has 'body' => (
    is        => 'rw',
    predicate => 1,
);

has 'config' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_config'
);

sub _build_config {
    Plerd::Config->new();
}

has 'date' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_date',
);

sub _build_date {
    my ( $self ) = @_;

    my $mtime = $self->source_file->stat->mtime;
    DateTime->from_epoch( epoch => $mtime, time_zone => 'local' );
}

has 'date_as_mysql' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_date_as_mysql',
);

sub _build_date_as_mysql {
    DateTime::Format::MySQL->format_datetime( shift->date );
}

has 'id' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_id',
);
sub _build_id {
    my  ($self) = @_;
    return encode_base64($self->uri);
}

has 'publication_file' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_publication_file',
    coerce  => \&_coerce_file,
);

sub _build_publication_file {
    my ( $self ) = @_;

    my $file;
    my $count = 0;
    while ( 1 ) {
        my $filename = 'notes-' . time() . '-' . ++$count . '.html';

        $file = Path::Class::File->new( $self->config->publication_directory,
            'notes', $filename, );

        if ( !-e $file ) {
            last;
        }
    }

    return $file;
}

has 'published_timestamp' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_published_timestamp'
);

sub _build_published_timestamp {
    my $self = shift;

    my $formatter = DateTime::Format::W3CDTF->new;
    my $timestamp = $formatter->format_datetime( $self->date );

    return $timestamp;
}

has 'source_file' => (
    is        => 'rw',
    predicate => 1,
    coerce    => \&_coerce_file,
);
has 'source_file_loaded' => ( is => 'rw', default => sub { 0 } );

has 'raw_body' => ( is => 'rw', predicate => 1 );

has 'tags'          => ( is => 'ro', default => sub { [] } );
has 'template_file' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_template_file'
);

sub _build_template_file {
    my ( $self ) = @_;
    Path::Class::File->new( $self->config->template_directory, "note.tt" );
}

has 'title' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_title',
    clearer => 1
);

sub _build_title {
    my ( $self ) = @_;

    # 1. Use the source file name
    if ( $self->source_file_loaded ) {
        if ( my $basename = $self->source_file->basename ) {
            $basename =~ s/\.txt$//i;
            $basename =~ s/[_-]/ /g;
            if ( $basename ) {
                return $basename;
            }
        }
    }

    # 2. OK, try the content
    my $raw = $self->body;
    $raw = _strip_html( $raw );

    if ( my @words = split /\s+/, $raw ) {
        my $size = @words - 1;
        my $max  = $size > 6 ? 6 : $size;
        return join( " ", @words[ 0 .. $max ] );
    }

    # 3. very sorry state of affairs if we get to this point
    my $basename = $self->publication_file->basename;
    $basename =~ s/\.html$//;
    return $basename;
}

has 'utc_date' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_utc_date'
);

sub _build_utc_date {
    my $self = shift;

    my $dt = $self->date->clone;
    $dt->set_time_zone( 'UTC' );
    return $dt;
}

has 'uri' => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_uri'
);

sub _build_uri {
    my ( $self ) = @_;
    my $base_uri = $self->config->base_uri;
    URI->new( $base_uri . "notes/" . $self->publication_file->basename );
}

has 'webmentions_display_uri' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_webmentions_display_uri',
);

sub _build_webmentions_display_uri {
    my $self = shift;
    if ( !$self->config->webmention_endpoint ) {
        return;
    }

    # WARNING: This assumes web mentions use whim
    #   https://github.com/jmacdotorg/whim
    my $clone = $self->config->webmention_endpoint->clone;
    $clone->path( $clone->path . 'display_wms' );
    $clone->query_form( 'url' => $self->uri );

    return $clone;
}

has 'webmentions_summary_uri' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_webmentions_summary_uri',
);

sub _build_webmentions_summary_uri {
    my $self = shift;
    if ( !$self->config->webmention_endpoint ) {
        return;
    }

    # WARNING: This assumes web mentions use whim
    #   https://github.com/jmacdotorg/whim
    my $clone = $self->config->webmention_endpoint->clone;
    $clone->path( $clone->path . 'summarize_wms' );
    $clone->query_form( 'url' => $self->uri );

    return $clone;
}

#-------------------
# Public Methods
#-------------------
sub can_publish {
    my ( $self ) = @_;

    if ( !$self->source_file_loaded ) {
        die( "Please load this note first" );
    }

    return $self->has_raw_body;
}

sub parse {
    my ( $self, $raw ) = @_;

    $raw //= $self->raw_body;
    my $urlPat = q[http(?:s)?://(?:\S+)];

    my @lines;
LINE:
    for my $line ( split /\r?\n/, $raw ) {
        my @words;

        # Handle u-in-reply-to and u-like-of
        # @todo: u-rsvp and u-repost-of
        #
        # If a line contains a "command string" followed by a URL,
        # mark it up in a specific way
        my %citations = (
            qq[^->\\s*($urlPat)\$] => sub {
                my ( $url ) = @_;
                sprintf(
                    q[<div class="h-cite u-in-reply-to reply-to">In reply to: <a rel="noopener noreferrer" href="%s">%s</a></div>],
                    $url, $url );
            },
            qq[^\\^\\s*($urlPat)\$] => sub {
                my ( $url ) = @_;
                sprintf(
                    q[<div class="h-cite u-like-of like"><abbr title="I like the following post">👍</abbr>: <a rel="noopener noreferrer" class="" href="%s">%s</a></div>],
                    $url, $url );

            },
        );

        while ( my ( $pattern, $decorator ) = each %citations ) {
            if ( $line =~ m{$pattern} ) {
                push @lines, $decorator->( $1 );
                next LINE;
            }
        }

        for my $word ( split( / /, $line ) ) {
            if ( $word =~ m!$urlPat!o ) {
                $word =
                    sprintf( q[<a rel="noopener noreferrer" href="%s">%s</a>],
                    $word, $word, );
            } elsif ( $word =~ m!^#([\w-]+)! ) {
                my $tag = Plerd::Model::Tag->new(
                    config => $self->config,
                    name   => $1
                );
                push @{ $self->tags }, $tag;
                $word =
                    sprintf( q[<a href="%s">#%s</a>], $tag->uri, $tag->name );
            }
            push @words, $word;
        }
        push @lines, join( " ", @words );
    }

    return $self->body( join( "\n", @lines ) );
}

sub load {
    my ( $self, $file ) = @_;

    if ( $self->has_source_file && !defined( $file ) ) {
        $file = $self->source_file;
    }

    die "Cannot find file $file\n" if !-e $file;

    my $new = $self->new(
        config      => $self->config,
        source_file => $file,
    );

    my $raw_body = $file->slurp();
    $new->raw_body( $raw_body );
    $new->parse();
    $new->source_file_loaded( 1 );

    return $new;
}

sub _coerce_file {
    my ( $thing ) = @_;

    if ( ref $thing eq 'Path::Class::File' ) {
        return $thing;
    }

    return Path::Class::File->new( $thing );
}

sub _strip_html {
    my ( $raw_text ) = @_;
    return unless $raw_text;

    my $stripped = HTML::Strip->new->parse( $raw_text );

    # Clean up apparently orphaned punctuation
    my $pat = q| ([;.,\?!])|;
    $stripped =~ s($pat)($1)g;

    return $stripped;
}

1;
