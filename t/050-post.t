use Modern::Perl '2018';

use Path::Class::File;
use Test::More;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Plerd::Config;
use Plerd::Model::Post;

Main();
exit;

#--------------
# Tests
#--------------
sub TestEmptyPost {
    ok( Plerd::Model::Post->new( source_file => "./first_post.md" ),
        "Created an empty post object" );
}

sub TestPostWithEmptySource {
    my $source_file = Path::Class::File->new( "$FindBin::Bin", "source_model",
        "no-title.md" );
    my $post = Plerd::Model::Post->new( source_file => $source_file );
    diag( "Source file: " . $source_file );

    ok( $post->load_source,  "Loading source file" );
    ok( !$post->has_title,   "Post has no title" );
    ok( $post->has_body,     "Post does have a body" );
    ok( !$post->can_publish, "Post cannot be published" );
    diag( "Published filename would be: " . $post->published_filename );
}

sub TestPostWithFormatedTitle {
    my $source_file = Path::Class::File->new( "$FindBin::Bin", "source_model",
        "formatted-title.md" );
    my $post = Plerd::Model::Post->new( source_file => $source_file );
    diag( "Source file: " . $source_file );

    ok( $post->load_source, "Loading source file" );
    ok( $post->has_title,   "Post has title: " . $post->title );
    ok( $post->has_body,    "Post does have a body" );
    ok( $post->can_publish, "Post can be published" );

    my $raw = $post->raw_body;
    diag( "Published filename would be: " . $post->published_filename );
    my $rewrite = $post->get_updated_source;
    if ( $raw ne $rewrite ) {
        diag(
            "Rewritten source changed: \n---Original:---\n$raw\n---New:---\n$rewrite"
        );
    }
}

sub TestFencedCodeBlock {
    my $source_file = Path::Class::File->new( "$FindBin::Bin", "source_model",
        "fenced-code-block.md" );

    my $post = Plerd::Model::Post->new( source_file => $source_file );
    $post->load_source;
    ok( $post->has_body, "Post has a body" );

    diag( "Source file: " . $source_file );
    diag( "Body:\n" . $post->body );
}

#--------------
# Helpers
#--------------
sub Main {
    setup();

    TestFencedCodeBlock();
    TestEmptyPost();
    TestPostWithEmptySource();
    TestPostWithFormatedTitle();

    teardown();

    done_testing();
}

sub setup {
}

sub teardown {
}
