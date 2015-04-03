use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More tests => 13;
use Fatal qw( mkdir );
use File::Spec::Functions;

use lib qw( t );
use PurgeTestCommons qw( touch xtempdir purge_any quote_win32_path );

my $topdir = xtempdir();
my $now = time;



my $dir = catdir( $topdir, "dir1" );
mkdir $dir;
touch( $now, catfile( $dir, 'file' ) );
ok( purge_any( '10-depth.conf', 'test_default_mindepth', [], { PATH => $dir }, ), "Running purge-any" ) or die;
ok( -e $dir, 'The given PATH was not deleted (depth: 1 by default)' );
ok( !-e catfile( $dir, 'file' ), 'The contents were deleted' );


touch( $now, catfile( $topdir, 'file2' ) );
ok( purge_any( '10-depth.conf', 'test_mindepth0', [], { PATH => catfile( $topdir, 'file2' ) }, ), "Running purge-any" ) or die;
ok( !-e catfile( $topdir, 'file2' ), 'The top path can be deleted with depth: 0' );


$dir = catdir( $topdir, 'dir3' );
mkdir $dir;
touch( $now, catfile( $dir, 'file' ) );
ok( purge_any( '10-depth.conf', 'test_maxdepth0', [], { PATH => $dir }, ), "Running purge-any" ) or die;
ok( -e catfile( $dir, 'file' ), 'The depth=1 file was untouched' );


$dir = catdir( $topdir, 'dir4' );
mkdir $dir;
mkdir catdir( $dir, 'level1' );
mkdir catdir( $dir, 'level1', 'level2' );
mkdir catdir( $dir, 'level1', 'level2', 'level3' );
mkdir catdir( $dir, 'level1', 'level2', 'level3', 'level4' );
touch( $now,
    catfile( $dir, 'level1.file' ),
    catfile( $dir, 'level1', 'level2.file' ),
    catfile( $dir, 'level1', 'level2', 'level3.file' ),
    catfile( $dir, 'level1', 'level2', 'level3', 'level4.file' ),
    catfile( $dir, 'level1', 'level2', 'level3', 'level4', 'level5.file' ),
);
ok( purge_any( '10-depth.conf', 'test_minmaxdepth', [], { PATH => $dir }, ), "Running purge-any" ) or die;
ok(  -e catfile( $dir, 'level1.file' ), 'Level 1 file was unscathed' );
ok( !-e catfile( $dir, 'level1', 'level2.file' ), 'Level 2 file was deleted' );
ok( !-e catfile( $dir, 'level1', 'level2', 'level3.file' ), 'Level 3 file was deleted' );
ok( !-e catfile( $dir, 'level1', 'level2', 'level3', 'level4.file' ), 'Level 4 file was deleted' );
ok(  -e catfile( $dir, 'level1', 'level2', 'level3', 'level4', 'level5.file' ), 'Level 5 file was unscathed' );

1;
