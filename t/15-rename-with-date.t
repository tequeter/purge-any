use strict;
use warnings;

use English qw( -no_match_vars );
use File::Spec::Functions;
use Test::More tests => 11;
use DateTime;

use lib qw( t );
use PurgeTestCommons qw( touch xtempdir purge_any quote_win32_path filespec_encode );

my $now = time;
my $day = 3600*24;
my $weird = "\xE9\xE7\xE0";
my $time_ref  = DateTime->now( time_zone => 'local' );
my $date      = $time_ref->strftime( '%F' );
my $datetime  = $time_ref->strftime( '%FT%H%M%S' );
my $time2_ref = $time_ref + DateTime::Duration->new( seconds => 1 );
my $datetime2 = $time2_ref->strftime( '%FT%H%M%S' ); # Second chance for slow computers


# Test rename_with_date action

my $dir = xtempdir();
touch( $now, filespec_encode( catfile( $dir, "cmd.log" ) ) );
touch( $now, filespec_encode( catfile( $dir, "iis.log" ) ) );
touch( $now, filespec_encode( catfile( $dir, "utf8_$weird.log" ) ) );
touch( $now, filespec_encode( catfile( $dir, "boo_$weird.log" ) ) );
touch( $now - $day, filespec_encode( catfile( $dir, "boo_$weird.log.$date" ) ) );
my $boo_mtime = -M filespec_encode( catfile( $dir, "boo_$weird.log.$date" ) );





ok( purge_any( '15-rename-with-date.conf', 'test_rename', [], {
    PATH  => quote_win32_path( $dir ),
}, ), "Running purge-any" ) or die;
ok( !-e filespec_encode( catfile( $dir, 'cmd.log' ) ),               'cmd.log was renamed' );
ok(  -e filespec_encode( catfile( $dir, "cmd.log.$date" ) ),         "cmd.log was renamed to cmd.log.$date" );
ok( !-e filespec_encode( catfile( $dir, 'iis.log' ) ),               'iis.log was renamed' );
ok(  -e filespec_encode( catfile( $dir, "iis.log.$datetime" ) )
  || -e filespec_encode( catfile( $dir, "iis.log.$datetime2" ) ),    "iis.log was renamed to iis.log.$datetime" );
ok( !-e filespec_encode( catfile( $dir, "utf8_$weird.log" ) ),       "utf8_$weird was renamed" );
ok(  -e filespec_encode( catfile( $dir, "utf8_$weird.log.$date" ) ), "utf8_$weird.log was renamed to utf8_$weird.log.$date" );

ok( !purge_any( '15-rename-with-date.conf', 'test_failed_rename', [], {
    PATH  => quote_win32_path( $dir ),
}, ), "Running purge-any" ) or die;
ok(  -e filespec_encode( catfile( $dir, "boo_$weird.log" ) ), "boo_$weird.log was not renamed because boo_$weird.log.$date already exists" );
is( -M filespec_encode( catfile( $dir, "boo_$weird.log.$date" ) ), $boo_mtime, "boo_$weird.log.$date was left untouched" );

ok( !purge_any( '15-rename-with-date.conf', 'test_invalid_spec', [], {
    PATH  => quote_win32_path( $dir ),
}, ), "Running purge-any" );

1;
