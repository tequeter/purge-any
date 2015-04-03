use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More tests => 10;
use Fatal qw( mkdir );
use File::Spec::Functions;

use lib qw( t );
use PurgeTestCommons qw( touch xtempdir purge_any quote_win32_path );

my $now = time;
my $day = 3600*24;


# Test the ANDing of predicates
my $dir = xtempdir();
foreach my $i ( 1 .. 2 )
{
    mkdir catdir( $dir, "dir$i" );
    foreach my $j ( 1 .. 3 )
    {
        touch( $now - $day, catfile( $dir, "dir$i", "file$j" ) );
    }
}
touch( $now, catfile( $dir, 'dir2', 'file2' ) );


ok( purge_any( '15-logic.conf', 'test_predicates_and', [], {
    PATH  => quote_win32_path( $dir ),
    _SEP_ => quote_win32_path( File::Spec->catfile( q{}, q{} ) ), # / or \\
}, ), "Running purge-any" ) or die;
ok(  -e catfile( $dir, 'dir1', 'file1' ), q{dir1 doesn't match the regexp } );
ok(  -e catfile( $dir, 'dir1', 'file2' ), q{dir1 doesn't match the regexp } );
ok(  -e catfile( $dir, 'dir1', 'file3' ), q{dir1 doesn't match the regexp } );
ok(  -e catfile( $dir, 'dir2', 'file1' ), q{dir2/file1 doesn't match the name (glob)} );
ok(  -e catfile( $dir, 'dir2', 'file2' ), q{dir2/file2 is too recent} );
ok( !-e catfile( $dir, 'dir2', 'file3' ), q{dir2/file3 matches all predicates} );


# Test multiple paths + no predicate
$dir = xtempdir();
mkdir catdir( $dir, 'a' );
mkdir catdir( $dir, 'b' );
touch( $now, catfile( $dir, 'a', 'file' ), catfile( $dir, 'b', 'file' ), );

ok( purge_any( '15-logic.conf', 'test_predicates_n_paths', [], {
    PATH1  => catdir( $dir, 'a' ),
    PATH2  => catdir( $dir, 'b' ),
}, ), "Running purge-any" ) or die;
ok( !-e catdir( $dir, 'a' ), 'Both paths were deleted' );
ok( !-e catdir( $dir, 'b' ), 'Both paths were deleted' );

1;
