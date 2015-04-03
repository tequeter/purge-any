use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More tests => 13;
use Fatal qw( mkdir );
use File::Spec::Functions;

use lib qw( t );
use PurgeTestCommons qw( xtempdir purge_any filespec_encode filespec_decode );

# Run purges on FS objects containing non-ASCII characters

my $weird = "\xE9\xE7\xE0";


my $dir = xtempdir();
# Assuming that your source file names are correctly encoded on your FS, by
# using system copy tools we ensure that the tests will be meaningful as well.
if ( $OSNAME eq 'MSWin32' )
{
    system "xcopy t\\10-utf8\\* $dir /e /q";
}
else
{
    system "cp -r t/10-utf8/* $dir";
}

# Check that we can access those even before running purge-any, or the test is meaningless
ok( -e filespec_encode( catfile( $dir, 'dir1', $weird ) ), 'We can access the test files' ) or die;
ok( -e filespec_encode( catfile( $dir, $weird, 'file' ) ), 'We can access the test files' ) or die;
ok( -e filespec_encode( catfile( $dir, 'dir2', $weird ) ), 'We can access the test files' ) or die;
ok( -e filespec_encode( catfile( $dir, 'Archives c-design JAC', 'Dossier Technique', '07E', 'Accessoires', "Sauvegarde_de_fl\xE9chage de base.cdr" ) ), 'We can access the test files' ) or die;

ok( purge_any( '10-utf8.conf', 'test', [], {
    PATH  => catdir( $dir, 'dir1' ),
}, ), "Running purge-any" ) or die;
ok( !-e filespec_encode( catfile( $dir, 'dir1', $weird ) ), 'A file under PATH with non-ASCII chars can be deleted (rmtree test)' );
ok( !-e filespec_encode( catdir(  $dir, 'dir1' ) ),        'PATH containing a file with non-ASCII chars can be deleted (rmtree test)' );


ok( purge_any( '10-utf8.conf', 'test', [], {
    PATH  => catdir( $dir, $weird ),
}, ), "Running purge-any" ) or die;
ok( !-e filespec_encode( catdir(  $dir, $weird ) ),         'Running a purge on a PATH containing non-ASCII chars can be deleted' );


ok( purge_any( '10-utf8.conf', 'test_eca', [], {
    PATH  => catdir( $dir, 'dir2' ),
}, ), "Running purge-any" ) or die;
ok( !-e filespec_encode( catfile(  $dir, 'dir2', $weird ) ), 'Name predicate on a file with non-ASCII chars works' );


ok( purge_any( '10-utf8.conf', 'cdesign', [], {
    PATH  => catdir( $dir, 'Archives c-design JAC', 'Dossier Technique', '07E' ),
}, ), "Running purge-any" ) or die;
ok( !-e filespec_encode( catfile( $dir, 'Archives c-design JAC', 'Dossier Technique', '07E', 'Accessoires', "Sauvegarde_de_fl\xE9chage de base.cdr" ) ), 'test file gets deleted' );


1;

