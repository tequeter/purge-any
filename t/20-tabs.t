use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More tests => 1;
use Fatal qw( mkdir );
use File::Spec::Functions;

use lib qw( t );
use PurgeTestCommons qw( touch xtempdir purge_any quote_win32_path );

my $topdir = xtempdir();
my $now = time;



my $dir = catdir( $topdir, "dir1" );
mkdir $dir;
touch( $now, catfile( $dir, 'file' ) );
ok( !purge_any( '20-tabs.conf', 'test_no_tabs', [], { PATH => $dir }, ), "Running purge-any" );

1;
