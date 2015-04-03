use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More tests => 22;
use Fatal qw( mkdir );
use File::Spec::Functions;
use File::stat qw();

use lib qw( t );
use PurgeTestCommons qw( touch xtempdir purge_any quote_win32_path filespec_encode filespec_decode );

my $now = time;
my $day = 3600*24;
my $weird = "\xE9\xE7\xE0";


# Test compression actions

my $dir = xtempdir();
# Assuming that your source file names are correctly encoded on your FS, by
# using system copy tools we ensure that the tests will be meaningful as well.
if ( $OSNAME eq 'MSWin32' )
{
    system "xcopy t\\15-compress\\* $dir /e /q";
}
else
{
    system "cp -r t/15-compress/* $dir";
    chmod 0612, catfile( $dir, 'README.txt' ) or die "chmod: $OS_ERROR";
    if ( $UID == 0 )
    {
        chown 4242, 4242, catfile( $dir, 'README.txt' ) or die "chown: $OS_ERROR";
    }
}
touch( $now - $day, filespec_encode( catfile( $dir, "README.txt" ) ) );


# Check that we can access those even before running purge-any, or the test is meaningless
ok( -e filespec_encode( catfile( $dir, "README.txt" ) ),             'We can access the test files' ) or die;
is( -M filespec_encode( catfile( $dir, "README.txt" ) ), 1,          'README.txt has mtime to -1 day' );
ok( -e filespec_encode( catfile( $dir, "README_$weird.txt" ) ),      'We can access the test files' ) or die;
ok( -e filespec_encode( catfile( $dir, "README2_$weird.txt" ) ),     'We can access the test files' ) or die;
ok( -e filespec_encode( catfile( $dir, "README2_$weird.txt.gz" ) ),  'We can access the test files' ) or die;
ok( -e filespec_encode( catfile( $dir, 'dir' ) ),                    'We can access the test files' ) or die;



ok( purge_any( '15-compress.conf', 'test_gzip_ascii', [], {
    PATH  => quote_win32_path( $dir ),
}, ), "Running purge-any" ) or die;
ok( !-e filespec_encode( catfile( $dir, "README.txt" ) ),       qq{README.txt was deleted} );
ok(  -s filespec_encode( catfile( $dir, "README.txt.gz" ) ),    qq{README.txt was compressed} );
ok( !-e filespec_encode( catfile( $dir, "README.txt.gz.gz" ) ), qq{README.txt.gz was not recompressed} );
SKIP: {
    my $stat_ref = File::stat::stat( catfile( $dir, 'README.txt.gz' ) );
    skip 'README.txt.gz did not get created', 3 if !$stat_ref;
    is( $stat_ref->mtime(), $now - $day, 'README.txt.gz has the same mtime than the original' );
    skip 'Meaningless on MSWin32', 3 if $OSNAME eq 'MSWin32';
    is( $stat_ref->mode() & 07777, 0612, 'The file mode was replicated on the archive' );
    skip 'UID/GID cannot be tested if not running as root', 2 if $UID != 0;
    is( $stat_ref->uid(), 4242, 'The file uid was replicated on the archive' );
    is( $stat_ref->gid(), 4242, 'The file gid was replicated on the archive' );
};

ok( purge_any( '15-compress.conf', 'test_gzip_utf8', [], {
    PATH  => quote_win32_path( $dir ),
}, ), "Running purge-any" ) or die;
ok(  -s filespec_encode( catfile( $dir, "README_$weird.txt.gz" ) ), qq{README_$weird.txt was compressed} );
ok( !-e filespec_encode( catfile( $dir, "README_$weird.txt" ) ),    qq{README_$weird.txt was deleted} );

ok( !purge_any( '15-compress.conf', 'test_gzip_exists', [], {
    PATH  => quote_win32_path( $dir ),
}, ), "Purge-any must fail on existing archive files" ) or die;
is(  -s filespec_encode( catfile( $dir, "README2_$weird.txt.gz" ) ), 4, qq{README2_$weird.txt.gz was left untouched} );
ok(  -e filespec_encode( catfile( $dir, "README2_$weird.txt" ) ),       qq{README2_$weird.txt was left untouched} );

ok( !purge_any( '15-compress.conf', 'test_gzip_dir', [], {
    PATH  => quote_win32_path( $dir ),
}, ), "Purge-any must fail on directories" ) or die;
ok( !-e catfile( $dir, 'dir.gz' ),      q{gzip did not attempt to compress a directory} );

1;
