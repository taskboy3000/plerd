package Plerd::Model::Post;

use Data::GUID;
use DateTime;
use DateTime::Format::W3CDTF;
use File::Basename;
use HTML::SocialMeta;
use HTML::Strip;
use JSON;
use Moo;
use Path::Class::File;
use Text::MultiMarkdown qw( markdown );
use URI;

use Plerd::Config;
use Plerd::Model::Tag;
use Plerd::SmartyPants;

our $gWPM = 200; # The words-per-minute reading speed to assume

has 'attributes' => (is => 'rw', default => sub { {} });
has 'attributes_have_changed' => ('is' => 'rw', default => sub { 0 });
has 'body' => (
    is => 'rw',
    predicate => 1, 
    coerce => \&_apply_markdown
);
has 'config' => (
    is => 'ro', 
    lazy => 1, 
    builder => '_build_config'
);
sub _build_config {
    Plerd::Config->new;    
}

# @todo: should have a builder, trigger looks like coersion, but isn't
has 'date' => (
    is => 'rw', 
    handles => [qw(month month_name day year ymd hms)],
    lazy => 1, 
    builder => '_build_date',
    trigger => \&_build_utc_date
);

sub _build_date {
    my ($self) = @_;

    my ( $filename_year, $filename_month, $filename_day ) =
        $self->source_file->basename =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/;

    # Set the post's date, using these rules:
    # * If the post has a time attribute in W3 format, use that
    # * Elsif the post's filename asserts a date, use midnight of that date,
    #   and also add a time attribute to the file.
    # * Else use right now, and also add a time attribute to the file.
    my $dt;
    my $now = DateTime->now( time_zone => 'local' );
    if ( $self->attributes->{ time } ) {
        eval {
            $dt = $self->config->datetime_formatter->parse_datetime( $self->attributes->{ time } );
            $dt->set_time_zone( 'local' );
            1;
        } or do {
            die 'Error processing ' . $self->source_file . ': '
                . 'The "time" attribute is not in W3C format.';
        };
    } elsif ( $filename_year ) {
        # The post specifies its day in the filename, but we still don't have a
        # publication hour.
        # If the filename's date is today (locally), use the current time.
        # Otherwise, use midnight of the provided date.
        my $ymd = $now->ymd( q{-} );
        if ( $self->source_file->basename =~ /^$ymd/ ) {
            $dt = $now;
        } else {
            $dt = DateTime->new(
                year => $filename_year,
                month => $filename_month,
                day => $filename_day,
                time_zone => 'local',
            );
        }
        $self->attributes_have_changed(1);
    } else {
        # The file doesn't name the time, *and* the file doesn't contain the date
        # in metadata (or else we wouldn't be here), so we'll just use right-now.
        $dt = $now;
        $self->attributes_have_changed(1);
    }

    my $date_string =
        $self->config->datetime_formatter->format_datetime( $dt );

    $self->attributes->{ time } = $date_string;

    return $dt;
}

has 'description' => (
    is => 'rw', 
    predicate => 1, 
    lazy => 1, 
    builder => '_build_description'
);
sub _build_description {
    my ($self) = @_;
    my $body = $self->stripped_body;
    my ( $description ) = $body =~ /^\s*(.*)\n/;
    $description || '';
}

has 'guid' => (is => 'rw', lazy => 1, builder => '_build_guid');
sub _build_guid {
    my ($self) =  @_;

    if ($self->attributes->{guid}) {
        return $self->attributes->{guid}
    }
    $self->attributes_have_changed(1);
    return Data::GUID->new;
}

# Inherit from the config
has 'image' => (
    is => 'rw',
    lazy => 1,
    predicate => 1,
    builder => '_build_image',
    coerce => \&_coerce_image,
);
sub _build_image {
    my $self = shift;
    if ($self->config->has_image) {
        return $self->config->image;
    }
    return;
}
sub _coerce_image {
    my ($img) = @_;
    if (ref $img eq 'URI') {
        return $img;
    }
    return URI->new( $img );
}

has 'image_alt' => (
    is => 'rw', 
    predicate => 1, 
    lazy => 1, 
    builder => '_build_image_alt'
);
sub _build_image_alt {
    my $self = shift;
    $self->config->image_alt;
}

has 'json' => (
    is => 'ro', 
    default => sub {  }
);

=pod
FIXME -- This is going to be handled by javascript
has 'newer_post' => (is => 'ro', lazy => 1, builder => '_build_newer_post');
sub _build_newer_post {
    my $self = shift;

    my $index = $self->plerd->index_of_post_with_guid->{ $self->guid };

    my $newer_post;
    if ( $index - 1 >= 0 ) {
        $newer_post = $self->plerd->posts->[ $index - 1 ];
    }

    return $newer_post;
}
has 'older_post' => (is => 'ro', lazy => 1, builder => '_build_older_post');
sub _build_older_post {
    my $self = shift;

    my $index = $self->plerd->index_of_post_with_guid->{ $self->guid };

    my $older_post = $self->plerd->posts->[ $index + 1 ];

    return $older_post;
}
=cut

has 'publication_file' => (
    is => 'ro',
    lazy => 1, 
    predicate => 1, 
    builder => '_build_publication_file'
);
sub _build_publication_file {
    my $self = shift;
    Path::Class::File->new(
        $self->config->publication_directory,
        $self->published_filename,
    );
}

# @todo: I am not clear that this is needed
has 'publication_file_mtime' => (
    is => 'ro',
    lazy => 1,
    predicate => 1,
    builder => '_builder_publication_file_mtime'
);
sub _build_publication_file_mtime {
    my ($self) = @_;
    if (-e $self->publication_file->stringify) {
        my @stat = $self->publication_file->stat;
        return $stat[9];
    }
    die("assert");
}

has 'published_filename' => (
    is => 'rw',
    lazy => 1, 
    builder => '_build_published_filename'
);
sub _build_published_filename {
    my $self = shift;

    if ($self->attributes->{published_filename}) {
        return $self->attributes->{published_filename};
    }
    $self->attributes_have_changed(1);
    my $filename = $self->source_file->basename;

    # If the source filename already seems Plerdish, just replace its extension.
    # Else, generate a Plerdish filename based on the post's date and title.
    if ( $filename =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/ ) {
        $filename =~ s/\..*$/.html/;
    } else {
        $filename = $self->title;
        my $stripper = HTML::Strip->new( emit_spaces => 0 );
        $filename = $stripper->parse( $filename );
        $filename =~ s/\s+/-/g;
        $filename =~ s/--+/-/g;
        $filename =~ s/[^\w\-]+//g;
        $filename = lc $filename;
        $filename = $self->date->ymd( q{-} ) . q{-} . $filename;
        $filename .= '.html';
    }

    return $filename;
}

has 'published_timestamp' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_published_timestamp'
);
sub _build_published_timestamp {
    my $self = shift;

    my $formatter = DateTime::Format::W3CDTF->new;
    my $timestamp = $formatter->format_datetime( $self->date );

    return $timestamp;
}

has ordered_attribute_names => (
    is =>'ro', 
    lazy => 1, 
    builder => '_build_ordered_attribute_names'
);
sub _build_ordered_attribute_names {
    return [ qw( title time published_filename guid tags) ];
}

has 'raw_body' => (is => 'rw', default => sub {''});

has 'reading_time' => (
    is => 'ro', 
    lazy => 1, 
    builder => '_build_reading_time'
);
sub _build_reading_time {
    my $self = shift;
    my @words = $self->stripped_body =~ /(\w+)\W*/g;
    return int ( scalar(@words) / $gWPM ) + 1;
}

has 'social_meta_tags' => (
    is => 'ro', 
    lazy => 1, 
    builder => '_build_social_meta_tags'
);
sub _build_social_meta_tags {
    my $self = shift;

    my $tags = '';
    my %targets = (
        twitter => 'twitter_id',
        opengraph => 'facebook_id',
    );

    if ( $self->socialmeta ) {
        for my $target ( keys %targets ) {
            my $id_method = $targets{ $target };
            my $has_method = 'has_' . $id_method;

            if ( $self->config->$has_method ) {
                eval {
                    $tags .=
                        $self->socialmeta->$target->create(
                            $self->socialmeta_mode
                        );
                    1;
                } or do {
                    warn "Couldn't create $target meta tags for "
                         . $self->source_file->basename
                         . ": $@\n";
                };
            }
        }
    }

    return $tags;
}

has 'socialmeta' => (
    is => 'ro',
    lazy => 1,
    predicate => 1,
    builder => '_build_socialmeta'
);
sub _build_socialmeta {
    my $self = shift;

    unless ( $self->has_image ) {
        # Neither this post nor this whole blog defines an image URL.
        # So, no social meta-tags for this post.
        return;
    }

    my %args = (
        site_name   => $self->config->title,
        title       => $self->title,
        description => $self->description,
        image       => $self->image->as_string,
        url         => $self->uri->as_string,
        image_alt   => $self->image_alt,
    );

    if ($self->config->has_facebook_id) {
        $args{ fb_app_id } = $self->config->facebook_id;
    }

    if ($self->config->has_twitter_id) {
        $args{ site } = '@' . $self->config->twitter_id;
    }

    my $socialmeta;
    eval {
        $socialmeta = HTML::SocialMeta->new( %args );
        1;
    } or do {
        warn "Couldn't build an HTML::SocialMeta object for post "
             . $self->source_file->basename
             . ": $@\n";
    };

    return $socialmeta;
}

has 'socialmeta_mode' => (
    is => 'rw',
    lazy => 1,
    builder => '_build_socialmeta_mode',
    default => sub {'summary'},
);
sub _build_socialmeta_mode {
    my ($self) = @_;

    my $mode = 'summary';
    if ($self->has_image) {
        $mode = 'featured_image';
    }

    return $mode;    
}

has 'source_file' => (
    is => 'rw',
    predicate => 1,
); 
has 'source_file_loaded' => (is => 'rw', default => sub { 0 });
has 'source_file_mtime' => (
    is => 'ro', 
    lazy => 1,
    clearer => 1, 
    builder => '_build_source_file_mtime'
);
sub _build_source_file_mtime {
    my ($self) = @_;
    if (-e $self->source_file->stringify) {
        my $stat = $self->source_file->stat();
        return $stat->mtime;
    } 

    die("assert - source file cannot be found: " . $self->source_file);
}

has 'stripped_body' => (
    is => 'ro', 
    lazy => 1, 
    builder => '_build_stripped_body'
);
sub _build_stripped_body {
    my $self = shift;
    return $self->_strip_html( $self->body );
}

has 'stripped_title' => (
    is => 'ro', 
    lazy => 1, 
    builder => '_build_stripped_title'
);
sub _build_stripped_title {
    my $self = shift;
    return $self->_strip_html( $self->title );
}

has 'tags' => (is => 'rw', lazy => 1, builder => '_build_tags', coerce => \&_coerce_tags);
sub _build_tags {
    my ($self) = @_;
    return $self->attributes->{tags};
}
sub _coerce_tags {
    my ($value) = @_;
    my @tags;
    if ($value) {
        my @tmp = split /\s*,\s*/, $value;
        for (@tmp) {
            push @tags, Plerd::Model::Tag->new(name => $_);
        }
    }

    return \@tags;
}

has 'title' => (
    is => 'rw', 
    predicate => 1, 
    lazy => 1, 
    builder => '_build_title',
    coerce => \&_coerce_title,
);
sub _build_title {
    my ($self) = @_;
    basename($self->source_file->basename, "\.md", "\.markdown");
}

has 'updated_timestamp' => (
    is => 'ro', 
    lazy => 1, 
    builder => '_build_updated_timestamp'
);
sub _build_updated_timestamp {
    my $self = shift;

    my $mtime = $self->source_file_mtime;

    my $formatter = DateTime::Format::W3CDTF->new;
    my $timestamp = $formatter->format_datetime(
        DateTime->from_epoch(
            epoch     => $mtime,
            time_zone => 'local',
        ),
    );

    return $timestamp;
}

has 'uri' => (
    is => 'ro', 
    lazy => 1, 
    builder => '_build_uri'
);
sub _build_uri {
    my $self = shift;

    my $base_uri = $self->config->base_uri;
    if ($base_uri =~ /[^\/]$/) {
        $base_uri .= '/';
    }

    return URI->new_abs(
        $self->published_filename,
        $base_uri,
    );
}

has 'utc_date' => (
    is => 'rw', 
    lazy => 1, 
    builder => '_build_utc_date'
);
sub _build_utc_date {
    my $self = shift;

    my $dt = $self->date->clone;
    $dt->set_time_zone( 'UTC' );
    return $dt;
}

#-------------------
# "Public" methods
#-------------------
sub load_source {
    my ($self, $source_file) = @_;

    if (defined $source_file) {
        $self->source_file($source_file);
    }

    if (!-e $self->source_file) {
        die("Cannot find source file: " . $self->source_file);
    }

    my $fh = $self->source_file->open('<:encoding(utf8)');
    my @ordered_attribute_names = qw( title time published_filename guid tags );
    my $line;
    while ( $line = <$fh> ) {
        chomp $line;

        my ($key, $value) = $line =~ /^\s*(\w+?)\s*:\s*(.*?)\s*$/;
        if ( $key ) {
            $key = lc $key;
            $self->attributes->{$key} = $value;
            
            if ($self->can($key)) {
                $self->$key($value);
            }

            unless ( grep { $_ eq $key } @{$self->ordered_attribute_names} ) {
                push @{$self->ordered_attribute_names}, $key;
            }
        } else {
            last;
        }
    }

    my $body;
    $body = "$line\n" if defined $line;
    while ( <$fh> ) {
        $body .= $_;
    }
    close $fh;
    $self->raw_body($body); # @thinkie: raw_title?
    $self->body($body); # this converts MD to HTML
    $self->source_file_loaded(1);
    return 1;
}

sub serialize_source {
    my ($self) = @_;

    # if $self->attributes_have_changed...
    my $new_content = '';
    for my $attribute_name ( @{$self->ordered_attribute_names} ) {
        if (defined $self->attributes->{ $attribute_name } ) {
            $new_content .= sprintf("%s: %s\n", $attribute_name, $self->attributes->{$attribute_name});
        }
    }
    $new_content .= "\n" . $self->raw_body . "\n";
    $self->source_file->spew( iomode=>'>:encoding(utf8)', $new_content );
    $self->_store($self->attributes)    
}

sub can_publish {
    my ($self) = @_;

    if ($self->has_title && $self->has_body) {
        return 1;
    }

    return;
}

# @remove to plerd controller
=pod
sub publish {
    my $self = shift;

    # Make <title>-ready text free of possible Markdown-generated HTML tags.
    my $stripped_title = $self->title;
    $stripped_title =~ s{</?(em|strong)>}{}g;

    my $html_fh = $self->publication_file->openw;
    my $template_fh = $self->plerd->post_template_file->openr;
    for ( $html_fh, $template_fh ) {
	    $_->binmode(':utf8');
    }

    $self->plerd->template->process(
        $template_fh,
        {
            plerd => $self->plerd,
            posts => [ $self ],
            title => $stripped_title,
            context_post => $self,
        },
	    $html_fh,
    ) || $self->plerd->_throw_template_exception( $self->plerd->post_template_file );

    $self->publication_file_mtime;
    $self->update_tag_db;
}
=cut

sub update_tag_db {
    my $self = shift;
    my $tags = $self->tags;

    @$tags 
}

#-------------------
# "Private" methods
#-------------------
sub _apply_markdown {
    my ($string) = @_;
    return Plerd::SmartyPants::process( markdown( $string || '' ) );
}

sub _coerce_title {
    my ($string) = @_;

    $string = _apply_markdown($string);
    $string =~ s{</?(em|strong)>}{}g;
    $string =~ s{</?p>\s*}{}g;

    return $string;
}

sub _strip_html {
    my ($self, $raw_text) = @_;

    my $stripped = HTML::Strip->new->parse( $raw_text );

    # Clean up apparently orphaned punctuation
    $stripped =~ s{ ([;.,\?\!])}{$1}g;

    return $stripped;
}

sub _store {
    my $self = shift;
    my ($data_ref) = @_;

    my $post_dir =  Path::Class::Dir->new(
        $self->config->database_directory,
        "posts"
    );

    unless ( -e $post_dir ) {
        $post_dir->mkpath;
    }

    my $file = Path::Class::File->new(
        $post_dir,
        $self->guid,
    );
    my $json = JSON->new->convert_blessed->utf8->canonical->pretty;
    $file->spew( $json->encode( $data_ref ) );
    return 1;
}

sub _retrieve {
    my $self = shift;

    my $file = Path::Class::File->new(
        $self->config->database_directory,
        "posts",
        $self->guid
    );

    if ( -e $file ) {
        my $json = JSON->new->convert_blessed->utf8;
        my $data;
        eval {
            my $in = $file->slurp;
            $data = $json->decode( $in );
            1;
        } or do {
            warn("Could not retrieve stored data: " . $@);
            return;
        };
        return $data;
    }

    return;
}

1;