# Joe Johnston <jjohn@taskboy.com>
package Plerd::Model::Note;
use Modern::Perl '2018';

use HTML::Strip;
use Path::Class::File;
use Moo;
use URI;

use Plerd::Config;
use Plerd::Model::Tag;

#-------------------------
# Attributes and Builders
#-------------------------
has 'body' => (is => 'rw', predicate => 1);

has 'config' => (
    is => 'ro', 
    lazy => 1, 
    builder => '_build_config'
);
sub _build_config {
    Plerd::Config->new();    
}

has 'publication_file' => (
    is => 'ro', 
    lazy => 1, 
    builder => '_build_publication_file'
);
sub _build_publication_file {
    my ($self) = @_;

    my $filename = "notes-" . time() . ".html";

    Path::Class::File->new(
        $self->config->publication_directory,
                           "notes",
                           $filename,
    );
}

has 'raw_body' => (is => 'rw', predicate => 1);

has 'tags' => (is => 'ro', default => sub { [] });
has 'template_file' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_template_file'
);
sub _build_template_file {
    my ($self) = @_;
    Path::Class::File->new($self->config->template_directory, "note.tt");
}

has 'title' => (
                is => 'rw',
                lazy => 1,
                builder => '_build_title',
                clearer => 1
);
sub _build_title {
    my ($self) = @_;
    my $raw = $self->body;
    $raw = _strip_html($raw);

    my @words = split /\s+/, $raw;
    if (@words) {
        my $size = @words - 1;
        my $max =  $size > 6 ? 6 : $size;
        return join(" ", @words[0..$max]);
    } else {
        my $basename = $self->publication_file->basename;
        $basename =~ s/\.html$//;
        return $basename;
    }

}

has 'uri' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_uri'
);
sub _build_uri {
    my ($self) = @_;
    my $base_uri = $self->config->base_uri;
    URI->new($base_uri . "/notes/" . $self->publication_file->basename);
}

#-------------------
# Public Methods
#-------------------
sub parse {
    my ($self, $raw) = @_;

    $raw //= $self->raw_body;

    my @lines;
    LINE:
    for my $line (split /\r?\n/, $raw) {
        my @words;
        # Handle u-in-reply-to and u-like-of
        # @todo: u-rsvp and u-repost-of
        #
        # If a line contains a "command string" followed by a URL,
        # mark it up in a specific way
        my $urlPat = q[http(?:s)?://(?:\S+)];
        my %citations = (
            qq[^->\\s*($urlPat)\$] => sub {
                my ($url) = @_;
                sprintf(q[<p class="h-cite reply-to">In reply to: <a rel="noopener noreferrer" class="u-in-reply-to" href="%s">%s</a></p>],
                    $url, $url
                );
            },
            qq[^\\^\\s*($urlPat)\$] => sub {
                my ($url) = @_;
                sprintf(q[<p class="h-cite like"><abbr title="I like the following post">👍</abbr>: <a rel="noopener noreferrer" class="u-like-of" href="%s">%s</a></p>],
                    $url, $url
                );

            },
        );

        while (my ($pattern, $decorator) = each %citations) {
            if ($line =~ m{$pattern}) {
                push @lines, $decorator->($1);
                next LINE;
            }
        }

        for my $word (split(/ /, $line)) {
            if ($word =~ m!^http(?:s)://(?:(\w+)\.){2,}!) {
                $word = sprintf(q[<a rel="noopener noreferrer" href="%s">%s</a>],
                                $word,
                                $word,
                               );
            } elsif ($word =~ m!^#([\w-]+)!) {
                my $tag = Plerd::Model::Tag->new(config => $self->config, name => $1);
                push @{ $self->tags }, $tag;
                $word = sprintf(q[<a href="%s">#%s</a>],
                                $tag->uri,
                                $tag->name
                               );
            }
            push @words, $word;
        }
        push @lines, join(" ", @words);
    }

    return $self->body(join("\n", @lines));
}

sub load {
    my ($self, $file) = @_;
    die "Cannot find file $file\n" if !-e $file;

    my $new = $self->new(config => $self->config);
    my $raw_body = $file->slurp();
    $new->raw_body($raw_body);
    $new->parse();

    return $new;
}

sub _strip_html {
    my ($raw_text) = @_;

    my $stripped = HTML::Strip->new->parse( $raw_text );

    # Clean up apparently orphaned punctuation
    $stripped =~ s{ ([;.,\?\!])}{$1}g;

    return $stripped;
}

1;
