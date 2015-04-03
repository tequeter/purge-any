use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More tests => 9;
use Fatal qw( mkdir );
use File::Spec::Functions;

use lib qw( t );
use PurgeTestCommons qw( touch xtempdir purge_any );

my $now = time;
my $day = 3600*24;


my $dir = xtempdir();
mkdir catdir( $dir, 'Organisation' );
mkdir catdir( $dir, 'Organisation', 'Informatique' );
mkdir catdir( $dir, 'Organisation', 'Informatique', 'PhotoIntegVentes' );
foreach my $country ( qw( Belgique Espagne France Italie ) )
{
    mkdir catdir( $dir, 'Organisation', 'Informatique', 'PhotoIntegVentes', $country );
    touch( $now,           catfile( $dir, 'Organisation', 'Informatique', 'PhotoIntegVentes', $country, 'PhotoIntegVentes_yesterday.csv' ) );
    touch( $now - 60*$day, catfile( $dir, 'Organisation', 'Informatique', 'PhotoIntegVentes', $country, 'PhotoIntegVentes_2_months_ago.csv' ) );
}

ok( purge_any( '50-hera.conf', 'hera', [], {
    'W:'    => $dir,
    '\\\\'  => File::Spec->catfile( q{}, q{} ), # / or \
}, ), "Running purge-any" ) or die;

foreach my $country ( qw( Belgique Espagne France Italie ) )
{
    ok(  -e catfile( $dir, 'Organisation', 'Informatique', 'PhotoIntegVentes', $country, 'PhotoIntegVentes_yesterday.csv' ),    "Yesterday's file was kept for country $country" );
    ok( !-e catfile( $dir, 'Organisation', 'Informatique', 'PhotoIntegVentes', $country, 'PhotoIntegVentes_2_months_ago.csv' ), "File from 2 months ago was purged for country $country" );
}

1;
