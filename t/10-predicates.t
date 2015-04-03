use strict;
use warnings;

use English qw( -no_match_vars );
use Test::More tests => 63;
use Fatal qw( mkdir );
use File::Spec::Functions;

use lib qw( t );
use PurgeTestCommons qw( touch xtempdir purge_any quote_win32_path );

my $dir = xtempdir();
my $now = time;
my $day = 3600*24;
my $min = 60;



my $dir2 = catfile( $dir, "dir2" );
mkdir $dir2;
mkdir catdir( $dir2, "subdir" );
# Create some old files
touch( $now - 3*$day,
    catfile( $dir2, '3 days ago 1' ),
    catfile( $dir2, '3 days ago 2' ),
    catdir(  $dir2, 'subdir' ),
    catfile( $dir2, 'subdir', 'otherfile' ),
);
# Create a recent file
touch( $now, catfile( $dir2, 'keepme' ) );


# Test --dry-run
ok( purge_any( '10-predicates.conf', 'test_recursion', [ qw( --dry-run ) ], { PATH => $dir2 }, ), "Running purge-any" ) or die;
ok( -e catfile( $dir2, '3 days ago 1' ), "--dry-run did not delete files (1)" );
ok( -e catfile( $dir2, 'keepme' ),       "--dry-run did not delete files (2)" );


# Test recursion & mtime
ok( purge_any( '10-predicates.conf', 'test_recursion', [], { PATH => $dir2 }, ), "Running purge-any" ) or die;
ok( !-e catfile( $dir2, '3 days ago 1' ),        "First file was deleted" );
ok( !-e catfile( $dir2, '3 days ago 2' ),        "Second file was deleted" );
ok( !-e catdir(  $dir2, 'subdir' ),              "subdirectory was deleted" );
ok( !-e catfile( $dir2, 'subdir', 'otherfile' ), "Third file was deleted" );
ok( -e $dir2,                                    "The top directory was untouched (too recent)" );
ok( -e catfile( $dir2, 'keepme' ),               'The recent file was untouched' );


# Test globbing
my $dir3 = catfile( $dir, 'dir3' );
mkdir $dir3;
mkdir catdir( $dir3, 'abc' );
touch( $now,
    catfile( $dir3, 'abc', 'file1.del' ),
    catfile( $dir3, 'abc', 'file2.del' ),
    catfile( $dir3, 'abc', 'file.delmenot' ),
    catfile( $dir3, 'abc', 'file1.old' ),
    catfile( $dir3, 'abc', 'file2.OLD' ),
    catfile( $dir3, 'abc', 'file3.oLd' ),
    catfile( $dir3, 'abc', 'delme-t(o)o' ),
    catfile( $dir3, 'abc', 'dontdelmet(o)o' ),
    catfile( $dir3, 'abc', 'NOTdelmet(o)o' ),
    catfile( $dir3, 'abc', 'keepme' ),
);
if ( $OSNAME eq 'linux' )
{
    touch( $now, catfile( $dir3, 'abc', 'glob*name?' ) );
}

ok( purge_any( '10-predicates.conf', 'test_name', [], { PATH => $dir3 }, ), "Running purge-any" ) or die;
ok( -e catdir( $dir3, 'abc' ),                    'the top dir still exists' );
ok( !-e catfile( $dir3, 'abc', 'file1.del' ),     '*.del matched' );
ok( !-e catfile( $dir3, 'abc', 'file2.del' ),     '*.del matched' );
ok( -e catfile( $dir3, 'abc', 'file.delmenot' ),  'the pattern is anchored to the right' );
ok( !-e catfile( $dir3, 'abc', 'file1.old' ),     'iname matched' );
ok( !-e catfile( $dir3, 'abc', 'file2.OLD' ),     'iname matched' );
ok( !-e catfile( $dir3, 'abc', 'file3.oLd' ),     'iname matched' );
ok( !-e catfile( $dir3, 'abc', 'delme-t(o)o' ),   'mixing "?", "*" and special characters works' );
ok( -e catfile( $dir3, 'abc', 'NOTdelmet(o)o' ),  q{'?' doesn't match multiple characters} );
ok( -e catfile( $dir3, 'abc', 'dontdelmet(o)o' ), q{the pattern is anchored to the left} );
ok( -e catfile( $dir3, 'abc', 'keepme' ),         q{the pattern does not match over directory boundaries (use the 'regex' predicate for that)} );
if ( $OSNAME eq 'linux' )
{
    TODO:
    {
        ok( !-e catfile( $dir3, 'glob*name\?' ), q{Glob wildcards can be escaped} );
    }
}
else
{
    SKIP:
    {
        skip 'This OS does not support file names with * or ?', 1;
    }
}

# Test regex
my $dir4 = catfile( $dir, 'dir4' );
mkdir $dir4;
mkdir catdir( $dir4, 'xyz' );
touch( $now,
    catfile( $dir4, 'file1.del' ),
    catfile( $dir4, 'file2.del' ),
    catfile( $dir4, 'file.delmenot' ),
    catfile( $dir4, 'file1.old' ),
    catfile( $dir4, 'file2.OLD' ),
    catfile( $dir4, 'file3.oLd' ),
    catfile( $dir4, 'delme-too' ),
    catfile( $dir4, 'xyz', 'file' ),
);

my $path_regexp_delim = catfile( $dir4, ' ' );
chop $path_regexp_delim;
ok( purge_any( '10-predicates.conf', 'test_regex', [], {
    PATH  => quote_win32_path( $dir4 ),
    _SEP_ => quote_win32_path( File::Spec->catfile( q{}, q{} ) ), # / or \\
}, ), "Running purge-any" ) or die;
ok( -e $dir4,                    'the top dir still exists' );
ok( !-e catfile( $dir4, 'file1.del' ),     '*.del matched' );
ok( !-e catfile( $dir4, 'file2.del' ),     '*.del matched' );
ok( !-e catfile( $dir4, 'file1.old' ),     'iregex matched' );
ok( !-e catfile( $dir4, 'file2.OLD' ),     'iregex matched' );
ok( !-e catfile( $dir4, 'file3.oLd' ),     'iregex matched' );
ok( !-e catfile( $dir4, 'delme-too' ),     'a complex regex works' );
ok( !-e catfile( $dir4, 'xyz', 'file' ),   q{the pattern matches anywhere in the whole path} );


# Advanced mtime test
my $dir5 = catfile( $dir, 'dir5' );
mkdir $dir5;
sub create_mtime_files
{
    touch( $now - 1*$day,           catfile( $dir5, 'yesterday' ) );
    touch( $now - ( 2*$day - 600 ), catfile( $dir5, 'two days ago minus 10 mins' ) );
    touch( $now - ( 2*$day + 600 ), catfile( $dir5, 'two days and 10 mins ago' ) );
    touch( $now - 3*$day,           catfile( $dir5, 'three days ago' ) );
}

create_mtime_files();
ok( purge_any( '10-predicates.conf', 'test_mtime2', [], { PATH => $dir5 } ), 'Running purge-any' ) or die;
ok(  -e catfile( $dir5, 'yesterday' ),                  q{yesterday doesn't match mtime 2} );
ok(  -e catfile( $dir5, 'two days ago minus 10 mins' ), q{2day- doesn't match mtime 2} );
ok( !-e catfile( $dir5, 'two days and 10 mins ago' ),   q{2day+ matches mtime 2} );
ok(  -e catfile( $dir5, 'three days ago' ),             q{3 days doesn't match mtime 2} );

create_mtime_files();
ok( purge_any( '10-predicates.conf', 'test_mtime-2', [], { PATH => $dir5 } ), 'Running purge-any' ) or die;
ok( !-e catfile( $dir5, 'yesterday' ),                  q{yesterday matches mtime -2} );
ok( !-e catfile( $dir5, 'two days ago minus 10 mins' ), q{2day- matches mtime -2} );
ok(  -e catfile( $dir5, 'two days and 10 mins ago' ),   q{2day+ doesn't match mtime -2} );
ok(  -e catfile( $dir5, 'three days ago' ),             q{3 days doesn't match mtime -2} );

create_mtime_files();
ok( purge_any( '10-predicates.conf', 'test_mtime+2', [], { PATH => $dir5 } ), 'Running purge-any' ) or die;
ok(  -e catfile( $dir5, 'yesterday' ),                  q{yesterday doesn't match mtime +2} );
ok(  -e catfile( $dir5, 'two days ago minus 10 mins' ), q{2day- doesn't match mtime +2} );
ok(  -e catfile( $dir5, 'two days and 10 mins ago' ),   q{2day+ doesn't match mtime +2} );
ok( !-e catfile( $dir5, 'three days ago' ),             q{three days matches mtime +2} );

# mmin test
my $dir5b = catfile( $dir, 'dir5b' );
mkdir $dir5b;
touch( $now - 1*$min,   catfile( $dir5b, '1 min ago' ) );
touch( $now - 1.5*$min, catfile( $dir5b, '1 min and 30 secs ago' ) );
touch( $now - 2.5*$min, catfile( $dir5b, '2 mins and 30 secs ago' ) );
touch( $now - 3*$min,   catfile( $dir5b, '3 mins ago' ) );

ok( purge_any( '10-predicates.conf', 'test_mmin2', [], { PATH => $dir5b } ), 'Running purge-any' ) or die;
ok(  -e catfile( $dir5b, '1 min ago' ),              '1 min ago' );
ok(  -e catfile( $dir5b, '1 min and 30 secs ago' ),  '1 min and 30 secs ago' );
ok( !-e catfile( $dir5b, '2 mins and 30 secs ago' ), '2 mins and 30 secs ago' );
ok(  -e catfile( $dir5b, '3 mins ago' ),             '3 mins ago' );

# Test type:d
my $dir6 = catfile( $dir, 'dir6' );
mkdir $dir6;
mkdir catdir( $dir6, 'adirectory' );
touch( $now, catfile( $dir6, 'afile' ) );
ok( purge_any( '10-predicates.conf', 'test_type_d', [], {
    PATH  => quote_win32_path( $dir6 ),
}, ), "Running purge-any" ) or die;
ok(  -e $dir6,                          'the top dir still exists' );
ok(  -e catfile( $dir6, 'afile' ),      'the file still exists' );
ok( !-e catfile( $dir6, 'adirectory' ), 'the directory was deleted' );

# Test empty
my $dir7 = catfile( $dir, 'dir7' );
mkdir $dir7;
mkdir catdir( $dir7, 'emptydir' );
touch( $now, catfile( $dir7, 'empty' ) );
do { open my $file, '>', catfile( $dir7, 'notempty' ); print {$file} "Hello.\n"; };
ok( purge_any( '10-predicates.conf', 'test_empty', [], {
    PATH  => quote_win32_path( $dir7 ),
}, ), "Running purge-any" ) or die;
ok(  -e $dir7,                        'the top dir still exists (not empty)' );
ok( !-e catfile( $dir7, 'empty' ),    'the empty file was deleted' );
ok(  -e catfile( $dir7, 'notempty' ), 'the not-empty file still exists' );
ok( !-e catfile( $dir7, 'emptydir' ), 'the empty directory was deleted' );

# Test empty
my $dir8 = catfile( $dir, 'dir8' );
mkdir $dir8;
touch( $now, catfile( $dir8, 'file' ) );
ok( purge_any( '10-predicates.conf', 'test_invalid_predicate', [], {
    PATH  => quote_win32_path( $dir8 ),
}, ), "Running purge-any" ) or die;
ok( -e catfile( $dir8, 'file' ), 'Invalid predicates never match' );

1;
