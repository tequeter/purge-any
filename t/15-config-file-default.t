use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More tests => 2;
use Fatal qw( mkdir chdir );
use File::Spec::Functions;
use File::Copy;

use lib qw( t );
use PurgeTestCommons qw( touch xtempdir purge_any quote_win32_path );

my $now = time;
my $day = 3600*24;


# Test the default config file path

my $dir = xtempdir();
touch( $now, catfile( $dir, 'file' ) );
copy( catfile( 't', '15-config-file-default.conf' ), catfile( $dir, 'purge-any.conf' ) );

my $curdir = File::Spec->rel2abs( curdir() );
my $script = File::Spec->rel2abs( catfile( curdir(), "purge-any.pl" ) );

chdir $dir;
my @extra_opts;
push @extra_opts, '-vvv' if $ENV{PURGE_TEST_DEBUG};
my $result = system $script, '-p', 'test', @extra_opts;
chdir $curdir;

if ( $result == -1 )
{
    die "Cannot execute $script: $OS_ERROR";
}
elsif ( $result & 127 )
{
    my $signal = $result & 127;
    die "Script died with signal $signal";
}
else
{
    my $return_code = ( $result >> 8 );
    is( $return_code, 0, 'purge-any.pl returned 0' );
}

ok( !-e catfile( $dir, 'file' ), 'The config file was used' );

1;

