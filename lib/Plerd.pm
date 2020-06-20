package Plerd;

our $VERSION = '1.821';

use Carp;
use DateTime;
use DateTime::Format::W3CDTF;
use Path::Class::Dir;
use Moo;
use Template;
use URI;

use Plerd::Post;
use Plerd::Tag;

#-------------------------
# Attributes and Builders
#-------------------------
# Note:
#   MooseX::AttributeShortcuts provides the default builder name for lazy attributes.
#   It requires Moose, but I do not want that dependency.
#   So, I have to type a lot more.
has 'archive_file' => (is => 'ro', lazy => 1, builder => '_build_archive_file');
sub _build_archive_file {
    my $self = shift;

    return Path::Class::File->new(
        $self->publication_directory,
        'archive.html',
    );
}

has 'archive_template_file' => (is => 'ro',lazy => 1, builder => '_build_archive_template_file');
sub _build_archive_template_file {
    my $self = shift;

    return Path::Class::File->new(
        $self->template_directory,
        'archive.tt',
    );
}

has 'author_email' => (is => 'ro', required => 1);
has 'author_name' => (is => 'ro', required => 1);
has 'base_uri' => (is => 'ro', required => 1);
has 'database_directory' => (is => 'ro', lazy => 1, builder => '_build_database_directory');
sub _build_database_directory {
    my $self = shift;

    return $self->_make_path( $self->database_path );
}

has 'database_path' => (is => 'ro', lazy => 1, builder => '_build_database_path');
sub _build_database_path {
    my $self = shift;

    if (defined $self->path) {
        return Path::Class::File->new($self->path . '/db');
    }
}

has 'datetime_formatter' => (is => 'ro', default => sub { DateTime::Format::W3CDTF->new });

# 'path' is the specification, 'directory' is the filesystem object
# Unclear we need both anymore
has 'directory' => (is => 'ro', lazy => 1, builder => "_build_directory");
sub _build_directory {
    my $self = shift;

    if ( defined $self->path ) {
        return Path::Class::Dir->new( $self->path );
    } else {
        return undef;
    }
}

has 'image' => (is => 'ro', predicate => 1);
has 'image_alt' => (is => 'ro', default => sub { "[image]" });
has 'index_of_post_with_guid' => (is => 'ro', lazy => 1, clearer => 1, builder => "_build_index_of_post_guid");
sub _build_index_of_post_with_guid {
    my $self = shift;

    my %index_of_post;
    my $current_index = 0;

    for my $post ( @{ $self->posts } ) {
        $index_of_post{ $post->guid } = $current_index++;
    }

    return \%index_of_post;
}

has 'index_of_post_with_url' => (is => 'ro', lazy => 1, clearer => 1, builder => '_build_index_of_post_with_url');
sub _build_index_of_post_with_url {
    my $self = shift;

    my %index_of_post;
    my $current_index = 0;

    for my $post ( @{ $self->posts } ) {
        $index_of_post{ $post->uri } = $current_index++;
    }

    return \%index_of_post;
}

has 'jsonfeed_file' => (is => 'ro', lazy => 1, builder => "_build_jsonfeed_file");
sub _build_jsonfeed_file {
    my $self = shift;

    return Path::Class::File->new(
        $self->publication_directory,
        'feed.json',
    );
}

has 'jsonfeed_template_file' => (is => 'ro', lazy => 1, builder => "_build_jsonfeed_template_file");
sub _build_jsonfeed_template_file {
    my $self = shift;

    return Path::Class::File->new(
        $self->template_directory,
        'jsonfeed.tt',
    );
}

has 'path' => (is => 'ro');
has 'post_parsing_errors' => (is => 'ro', lazy => 1, builder => '_build_post_parsing_errors');
sub _build_post_parsing_errors {
    # These are a list of source_file => error
    return [];
}
# clearer requires MooseX::AttributeShortcuts
sub clear_post_parsing_errors { @{ shift->post_parsing_errors } = () }


has 'post_template_file' => (is => 'ro',lazy => 1, builder => '_build_post_template_file');
sub _build_post_template_file {
    my $self = shift;

    return Path::Class::File->new(
        $self->template_directory,
        'post.tt',
    );
}

#has 'posts' => (is => 'ro', lazy => 1, clearer => 1, builder => "_build_posts"); 
#sub _build_posts {
#    my $self = shift;
#    my @posts;
#
#    @posts = sort { $b->date <=> $a->date }
#                map { Plerd::Post->new( plerd => $self, source_file => $_ ) }
#                @${ $self->get_source_files }
#    ;
#
#    return \@posts;
#}
#

has 'publication_directory' => (is => 'ro', lazy => 1, builder => "_build_publication_directory");
sub _build_publication_directory {
    my $self = shift;

    return $self->_make_path( $self->publication_path );
}

has 'publication_path' => (is => 'ro', lazy => 1, builder => "_build_publication_path");
sub _build_publication_path {
    my $self = shift;
    return $self->path . "/docroot";
}

has 'recent_file' => (is => 'ro', lazy => 1, builder => '_build_recent_file');
sub _build_recent_file {
    my $self = shift;

    return Path::Class::File->new(
        $self->publication_directory,
        'recent.html',
    );
}

has 'recent_posts' => (is => 'ro', lazy => 1, clearer => 1, builder => "_build_recent_posts");
sub _build_recent_posts {
    my $self = shift;

    my @recent_posts = ();

    for my $post ( @{ $self->posts } ) {

        my $did_update = 0;

        if ( @recent_posts < $self->recent_posts_maxsize ) {
            push @recent_posts, $post;
            $did_update = 1;
        }
        elsif ( $post->date > $recent_posts[ -1 ]->date ) {
            pop @recent_posts;
            push @recent_posts, $post;
            $did_update = 1;
        }

        if ( $did_update ) {
            @recent_posts = sort { $b->date <=> $a->date } @recent_posts;
        }
    }

    return \@recent_posts;
}

has 'recent_posts_maxsize' => (is => 'ro', default => 10);
has 'rss_file' => (is => 'ro', lazy => 1, builder => "_build_rss_file");
sub _build_rss_file {
    my $self = shift;

    return Path::Class::File->new(
        $self->publication_directory,
        'atom.xml',
    );
}

has 'rss_template_file' => (is => 'ro', lazy => 1, builder => '_build_rss_template_file');
sub _build_rss_template_file {
    my $self = shift;

    return Path::Class::File->new(
        $self->template_directory,
        'atom.tt',
    );
}

has 'source_directory' => (is => 'ro', lazy => 1, builder => '_build_source_directory');
sub _build_source_directory {
    my $self = shift;

    return $self->_make_path( $self->source_path );
}

has 'source_path' => (is => 'ro', lazy => 1, builder => "_build_source_path");
sub _build_source_path {
    my $self = shift;
    if (defined $self->path) {
        return $self->path . "/source";
    }

    return undef;    
}

has 'tag_case_conflicts' => (is => 'rw', default => sub { {} });
has 'tags_index_uri' => (is => 'ro', lazy => 1, builder => '_build_tags_index_uri');
sub _build_tags_index_uri {
    my $self = shift;
    return URI->new_abs(
        'tags/',
        $self->base_uri,
    );
}

has 'tags_map' => (is => 'ro', lazy => 1, builder => '_build_tags_map');
sub _build_tags_map { {} };

has 'tags_publication_directory' => (is => 'ro', lazy => 1, builder => '_build_tags_publication_directory');
sub _build_tags_publication_directory {
    my $self = shift;

    return $self->_make_path( $self->tags_publication_path );
}

has 'tags_publication_path' => (is => 'ro', lazy => 1, builder => '_build_tags_publication_path');
sub _build_tags_publication_path {
    my ($self) = @_;
    if ($self->path) {
        return $self->path . '/tags';
    }
}

has 'tags_template_file' => (is => 'ro', lazy => 1, builder => '_build_tags_template_file');
sub _build_tags_template_file {
    my $self = shift;

    return Path::Class::File->new(
        $self->template_directory,
        'tags.tt',
    );
}

has 'template' => (is => 'ro',lazy => 1, builder => '_build_template');
sub _build_template {
    my $self = shift;

    return Template->new( {
        INCLUDE_PATH => $self->template_directory,
        FILTERS => {
            json => sub {
                my $text = shift;
                $text =~ s/"/\\"/g;
                $text =~ s/\n/\\n/g;
                return $text;
            },
        },
        ENCODING => 'utf8',
    } );
}

has 'template_directory' => (is => 'ro', lazy => 1, builder => '_build_template_directory');
sub _build_template_directory {
    my $self = shift;

    return $self->_make_path( $self->template_path );
}

has 'template_path' => (is => 'ro', lazy => 1, builder => '_build_template_path');
sub _build_template_path {
    my ($self) = @_;
    if ($self->path) {
        return $self->path . '/templates';
    } 
    return undef;
}

has 'title' => (is => 'ro', required => 1);

#---------
# Build
#---------
sub BUILD {
    my $self = shift;

    if (! $self->path ) {
        for my $subdir_type ( qw( source template publication database ) ) {
            eval {
                my $method = "${subdir_type}_directory";
                my $dir = $self->$method;
                1;
            } or do {
                die "Can't create a new Plerd object, due to insufficient "
                    . "configuration: $@";
            };
        }
    }

    return $self;
}

#------------------
# "Public" Methods
#------------------
# Returns a list ref of Path::Class:Files to found source files
# Note, this is intentially not an attribute, eschew caching
sub get_source_files {
    my ($self) = @_;

    my @rawFiles = glob($self->source_directory . '/*.md'), 
                    glob($self->source_directory . "/*.markdown");

    my @sources;
    for my $rawFile (@rawFiles) {
        push @sources, Path::Class::File->new($rawFile);
    }

    # Sort by the non-extension version of the base filename
    # Need to Schwartian Transform to remove extensions
    # Hard to believe Path::Class::File->basename does not to
    # this.
    return [
            map { $_->[0] }
            sort { $a->[1] cmp $b->[1] }
            map {
                my $bn = $_->basename;
                $bn =~ s{\.(?:md|markdown)$}{}; 
                [ $_ => $bn ]
            } @sources
    ];
}

sub get_posts {
    my ($self) = @_;
    my @posts;
    $self->clear_post_parsing_errors;
    for my $sourceFile (@{ $self->get_source_files }) {
        my $post;
        eval {
            $post = Plerd::Post->new(plerd => $self, source_file => $sourceFile);
            1;
        } or do {
            push @{$self->post_parsing_errors}, [ $sourceFile => $@ ];
            next;
        };

        push @posts, $post; 
    }
    return \@posts;
}

# Sort the list of posts by intended publication date
sub sort_posts {
    my ($self, $posts) = @_;

    if (defined $posts && ref $posts ne ref []) {
        die("assert");
    }

    $posts ||= $self->get_posts;

    return [ sort { $b->date <=> $a->date } @$posts ]; 
}

# @todo: This should really just publish new posts and update tags
sub publish {
    my $self = shift;
 
    return $self->publish_all;
}

sub publish_all {
    my $self = shift;

    for my $post ( @{ $self->posts } ) {
        $post->publish;
    }

    $self->publish_tag_indexes;
    $self->report_tag_case_conflicts;

    $self->publish_archive_page;

    $self->publish_recent_page;
    $self->publish_rss;
    $self->publish_jsonfeed;

    $self->clear_recent_posts;
    $self->clear_posts;
    $self->clear_post_index_hash;
    $self->clear_post_url_index_hash;

    $self->tags_map( {} );
    $self->tag_case_conflicts( {} );
}

# Create a page that lists all available tags with
# links to those pages that list the articles that
# have those tags
sub publish_tag_indexes {
    my $self = shift;

    my $tag_map = $self->tags_map;

    # Commentary: Ideally we'd just pass a sorted array of tag objects
    # to the template. But alas said template was designed before tags were
    # objects, and I didn't want to make Plerd users have to go mess around
    # in their templates in between minor Plerd versions. And thus, we
    # pull out some tag data into a hash and pass that in, instead.

    # Create all the individual tag pages
    for my $tag (values %$tag_map) {

        $self->template->process(
            $self->tags_template_file->open('<:encoding(utf8)'),
            {
                self_uri => $tag->uri,
                is_tags_page => 1,
                tags => { $tag->name => $tag->posts },
                plerd => $self,
            },
            $self->_make_tags_publication_file($tag->name)->open('>:encoding(utf8)'),
            ) || $self->_throw_template_exception( $self->tags_template_file );
    }

    # Create the tag index
    my %simplified_tag_map;
    for my $tag (values %$tag_map) {
        $simplified_tag_map{ $tag->name } = $tag->posts;
    }
    $self->template->process(
        $self->tags_template_file->open('<:encoding(utf8)'),
        {
            self_uri => $self->tags_index_uri,
            is_tags_index_page => 1,
            is_tags_page => 1,
            tags => \%simplified_tag_map,
            plerd => $self,
        },
        $self->_make_tags_publication_file->open('>:encoding(utf8)'),
        ) || $self->_throw_template_exception( $self->tags_template_file );

}

sub publish_recent_page {
    my $self = shift;

    $self->template->process(
        $self->post_template_file->open('<:encoding(utf8)'),
        {
            plerd => $self,
            posts => $self->recent_posts,
            title => $self->title,
        },
        $self->recent_file->open('>:encoding(utf8)'),
    ) || $self->_throw_template_exception( $self->post_template_file );

    my $index_file =
        Path::Class::File->new( $self->publication_directory, 'index.html' );
    symlink $self->recent_file, $index_file;
}

sub publish_rss {
    my $self = shift;

    $self->_publish_feed( 'rss' );
}

sub publish_jsonfeed {
    my $self = shift;

    $self->_publish_feed( 'jsonfeed' );
}

sub post_with_url {
    my $self = shift;
    my ( $url ) = @_;

    my $index = $self->index_of_post_with_url->{ $url };
    if ( defined $index ) {
        return $self->posts->[ $self->index_of_post_with_url->{ $url } ];
    }
    else {
        return;
    }
}

# @todo: Why is this method marked private?
sub _publish_feed {
    my $self = shift;
    my ( $feed_type ) = @_;

    my $template_file_method = "${feed_type}_template_file";
    my $file_method          = "${feed_type}_file";

    return unless -e $self->$template_file_method;

    my $formatter = $self->datetime_formatter;
    my $timestamp =
        $formatter->format_datetime( DateTime->now( time_zone => 'local' ) )
    ;

    $self->template->process(
        $self->$template_file_method->open('<:encoding(utf8)'),
        {
            plerd => $self,
            posts => $self->recent_posts,
            timestamp => $timestamp,
        },
        $self->$file_method->open('>:encoding(utf8)'),
    ) || $self->_throw_template_exception( $self->$template_file_method );
}

sub publish_archive_page {
    my $self = shift;

    my $posts_ref = $self->posts;

    $self->template->process(
        $self->archive_template_file->open('<:encoding(utf8)'),
        {
            plerd => $self,
            posts => $posts_ref,
        },
        $self->archive_file->open('>:encoding(utf8)'),
    ) || $self->_throw_template_exception( $self->archive_template_file );

}

### Helper methods
# Given a Path::Class::File or Path::Class::Dir make the directory
sub _make_path {
    my ($self, $path) = @_;

    if (!$path) {
        die("assert - no path given to _make_path");
    }

    if (ref $path eq 'Path::Class::File') {
        if (-e $path->parent->stringify) {
            return $path->parent;
        }

        return $self->_make_path($path->parent);
    } elsif (ref $path eq 'Path::Class::Dir') {
        if ( -e $path->stringify) {
            return $path;
        }
        $path->mkpath(0, 0755);
        return $path;
    } elsif (!ref $path) {
        # assume someone passed in a path as a string
        return $self->_make_path(Path::Class::Dir->new($path));
    }

    die("assert - unhandled object " . $path);    
}

sub _throw_template_exception {
    my $self = shift;
    my ( $template_file ) = @_;

    my $error = $self->template->error;

    die "Publication interrupted due to an error encountered while processing "
        . "template file $template_file: $error\n";
}


#### Tag-related builders & methods
# This is dynamically computed and not a good fit for a Moo property
sub has_tags {
    my $self = shift;
    my $tags_map = $self->tags_map;

    return scalar(keys(%$tags_map)) ? 1 : 0;
}

# Return either the tags/index.html file
# or a tags/TAGNAME.html file if given a tag
sub _make_tags_publication_file {
    my ($self, $tag) = @_;
    $tag //= 'index';

    my $tags_dir = $self->_make_path($self->publication_directory,
                                     $self->_build_tags_publication_directory);

    my $file = Path::Class::File->new($tags_dir,
                                      "$tag.html");

    return $file;
}

sub tag_named {
    my ( $self, $tag_name ) = @_;

    my $key = lc $tag_name;
    my $tag = $self->tags_map->{ $key };

    if ( $tag ) {
        $tag->ponder_new_name( $tag_name );
    } else {
        $tag = Plerd::Tag->new(
            name => $tag_name,
            plerd => $self,
        );
        $self->tags_map->{ $key } = $tag;
    }

    return $tag;
}

sub tag_uri {
    my ( $self, $tag_name ) = @_;

    my $tag = $self->tag_named( $tag_name );

    return $tag ? $tag->uri : $self->tags_index_uri;
}

sub add_tag_case_conflict {
    my ( $self, $conflicting_tag, $existing_tag ) = @_;

    return unless $conflicting_tag ne $existing_tag;

    $self->tag_case_conflicts->{lc $existing_tag}->{$conflicting_tag} = 1;
    $self->tag_case_conflicts->{lc $existing_tag}->{$existing_tag} = 1;
}

sub report_tag_case_conflicts {
    my $self = shift;

    unless ( keys %{$self->tag_case_conflicts} ) {
        return;
    }

    my $warning = "This blog's tags include the following case-conflicts:\n";

    foreach ( keys %{$self->tag_case_conflicts} ) {
        my $conflicts = join ', ', sort keys %{$self->tag_case_conflicts->{$_}};
        $warning .= "$conflicts\n";
    }

    $warning .= "This can lead to unexpected behavior, broken links, and other\n"
             . "sadnesses and regrets. Please normalize these tags!\n";

    warn $warning;
}

1;

