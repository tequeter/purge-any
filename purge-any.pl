#!/usr/bin/perl

use 5.008;
use strict;
use warnings;

# Documentation: pod2text -lc purge-any.pl |less -r

use English qw( -no_match_vars );
use Getopt::Long;
use Pod::Usage;
use IPC::Open3;
use Log::Log4perl qw( :easy );
use Log::Log4perl::Appender::Screen; # For PAR
use Log::Log4perl::Layout::SimpleLayout; # For PAR
use DateTime;
use DateTime::TimeZone::Europe::Berlin; # For PAR
use DateTime::TimeZone::Europe::Paris;  # For PAR
use DateTime::TimeZone::Europe::Madrid; # For PAR
use DateTime::TimeZone::Europe::Rome;   # For PAR
use DateTime::TimeZone::Asia::Shanghai; # For PAR
use List::Util qw( max );
use YAML::XS;
use File::Path qw();
use File::Temp;
use Encode;
use Encode::Byte; # For PAR
use List::Util qw( first );
use File::stat qw();
use File::Copy qw();
if ( $OSNAME eq 'MSWin32' )
{
    require Win32::Codepage::Simple;
    require DateTime::TimeZone::Local::Win32;
}
else
{
    require encoding; # For its utility function
}
# More PAR support : datetime_now is called once at compile-time, see below

our $VERSION = 1.013_006;
my $DEFAULT_MIN_DEPTH = 1;
my $DEFAULT_MAX_DEPTH = 1024;
my $GZIP_CMD;
BEGIN { $GZIP_CMD = '/usr/bin/gzip'; }

use Memoize;
memoize( 'get_locale_encoding' );
memoize( 'fileglob_to_re' );
memoize( 'datetime_now' );

Log::Log4perl->easy_init( $ERROR );
my $logger_ref = get_logger();


main();

sub main
{
    my $config_file;
    my $profile_name;
    my $verbosity = 0;
    my $show_config = 0;
    my $dry_run = 0;
    
    DEBUG "Parsing options";
    Getopt::Long::Configure( "bundling" );
    GetOptions( 'config-file|f=s'    => \$config_file,
                'profile|p=s'        => \$profile_name,
                'show-config'        => sub { $show_config = 2; },
                'dry-run'            => sub { $dry_run = 2; },
                'help'               => sub { pod2usage( 1 ); },
                'man'                => sub { pod2usage( -exitstatus => 0, -verbose => 2 ); },
                'verbose|v+'         => \$verbosity,
                'version'            => sub { version(); exit 0; },
    ) or pod2usage( 255 );
    $logger_ref->more_logging( max( $verbosity, $show_config ) );
    
    if ( !$config_file )
    {
        DEBUG "--config-file not specified, trying to figure out the configuration file path";
        $config_file = find_config_file();
    }
    if ( !$profile_name )
    {
        DEBUG "--profile not specified, using the computer name";
        $profile_name = find_config_name();
    }
    my $config_ref = load_config_file( $config_file );
    my $profile_ref = get_profile( $config_ref, $profile_name );
    if ( $show_config )
    {
        check_profile( $profile_ref );
        show_profile( $profile_ref );
        DEBUG "--show-config mode: exiting";
        exit 0;
    }
    
    setup_logging( $config_ref, $profile_ref );
    $logger_ref->more_logging( max( $verbosity, $dry_run ) );

    check_profile( $profile_ref );

    if ( execute_all_purges( $profile_ref, $dry_run ) )
    {
        DEBUG "Exiting with code 0 (success)";
        exit 0;
    }
    else
    {
        DEBUG "Exiting with code 1 (error)";
        exit 1;
    }
}

sub version
{
    print STDERR "purge-any version $VERSION\n";
    return;
}

sub find_config_file
{
    # This function used to be much more complex with several hardcoded paths
    # to look into per OS. Now the specification says to use -f or to look in
    # the current directory. Look in changeset 45c24a673e34 if you need to
    # recover this feature.

    my $default_config_path = File::Spec->catfile( File::Spec->curdir(), 'purge-any.conf' );

    if ( -e $default_config_path )
    {
        INFO "Found configuration file $default_config_path";
        return $default_config_path;
    }
    else
    {
        LOGDIE "Could not find the configuration file in the current directory and -f was not specified";
    }
}

sub find_config_name
{
    if ( my $hostname = `hostname` )
    {
        chomp $hostname;
        INFO "Found hostname '$hostname'";
        return lc $hostname;
    }
    else
    {
        LOGDIE "Could not determine computer name using external command 'hostname'";
    }
}

sub load_config_file
{
    my ( $file ) = @_;

    open my $file_ref, '<', $file or LOGDIE "open $file: $OS_ERROR";
    my $config_text = do { local $/; readline $file_ref; };
    check_for_tabs( $config_text );
    my $config_ref = Load( $config_text );
    if ( ref $config_ref eq 'HASH' )
    {
        INFO "Parsed $file contents";
        return $config_ref;
    }
    else
    {
        LOGDIE "Invalid $file contents";
    }
}

sub check_for_tabs
{
    my ( $config_text ) = @_;

    my @lines = split /\n/, $config_text;
    for ( my $i = 0; $i < @lines; ++$i )
    {
        if ( $lines[$i] =~ /\t/ )
        {
            my $lineno = $i + 1;
            LOGDIE "There is a TAB character in the configuration file at line $lineno";
        }
    }

    return;
}

sub get_profile
{
    my ( $config_ref, $profile_name ) = @_;

    if ( exists $config_ref->{profiles}->{$profile_name} )
    {
        if ( ref $config_ref->{profiles}->{$profile_name} eq 'HASH' )
        {
            return $config_ref->{profiles}->{$profile_name};
        }
        else
        {
            LOGDIE "Invalid configuration profile '$profile_name' contents";
        }
    }
    else
    {
        LOGDIE "Could not find the profile '$profile_name' in the config file";
    }
}

sub show_profile
{
    my ( $profile_ref ) = @_;
    INFO Dump( $profile_ref );
    return;
}

sub setup_logging
{
    my ( $config_ref, $profile_ref ) = @_;

    my $log4perl_config;
    if ( ref $profile_ref eq 'HASH' && exists $profile_ref->{logging} )
    {
        $log4perl_config = $profile_ref->{logging};
        DEBUG "Using the host section 'logging' entry as Log4perl configuration";
    }
    elsif ( exists $config_ref->{logging}->{$OSNAME} )
    {
        $log4perl_config = $config_ref->{logging}->{$OSNAME};
        DEBUG "Using the global 'logging' entry as Log4perl configuration";
    }
    else
    {
        DEBUG "No Log4perl configuration found";
    }

    if ( $log4perl_config )
    {
        DEBUG "Configuring Log4perl with:\n", $log4perl_config;
        Log::Log4perl::init( \$log4perl_config );
    }

    return;
}

sub check_profile
{
    my ( $profile_ref ) = @_;

    if ( ref $profile_ref ne 'HASH' )
    {
        LOGDIE "Invalid profile data (expected a hash)";
    }
    if ( !exists $profile_ref->{purges} || ref $profile_ref->{purges} ne 'ARRAY' )
    {
        LOGDIE "Invalid profile/purges data (expected an array containing an array";
    }
        
    my $purge_index = 1;
    foreach my $purge_ref ( @{ $profile_ref->{purges} } )
    {
        ++$purge_index;
        if ( ref $purge_ref ne 'HASH' )
        {
            LOGDIE "Invalid profile/purges[$purge_index] data (expected a hash)";
        }

        $purge_ref->{'predicates'} ||= [];
        foreach my $key ( qw( description action paths predicates ) )
        {
            if ( !exists $purge_ref->{$key} )
            {
                LOGDIE "Missing required key $key in profile/purges[$purge_index]";
            }
            if ( ( $key eq 'paths' || $key eq 'predicates' ) && ref $purge_ref->{$key} ne 'ARRAY' )
            {
                LOGDIE "Invalid profile/purges[$purge_index]/$key data (expected an array)";
            }
            if ( $key eq 'predicates' )
            {
                my $pred_index = 1;
                foreach my $pred_ref ( @{ $purge_ref->{$key} } )
                {
                    ++$pred_index;
                    if ( ref $pred_ref ne 'HASH' )
                    {
                        LOGDIE "Invalid profile/purges[$purge_index]/predicates[$pred_index]";
                    }
                    
                    keys %$pred_ref; # Reset for "each"
                    my ( $pred_name, $pred_value ) = each %$pred_ref;
                    if ( !defined $pred_name || !defined $pred_value )
                    {
                        LOGDIE "Incomplete predicate profile/purges[$purge_index]/predicates[$pred_index]";
                    }

                    if ( $pred_name eq 'empty' && $pred_value ne 'yes' )
                    {
                        LOGDIE "Invalid value for 'empty' predicate profile/purges[$purge_index]/predicates[$pred_index]";
                    }

                    if ( $pred_name eq 'mtime' && $pred_value !~ /^[+-]?\d+$/ )
                    {
                        LOGDIE "Invalid numeric predicate format profile/purges[$purge_index]/predicates[$pred_index]";
                    }
                }
            }
        }

        if ( exists $purge_ref->{mindepth} && ( !defined $purge_ref->{mindepth} || $purge_ref->{mindepth} !~ /^\d+$/ ) )
        {
            LOGDIE "Invalid mindepth (must be a number) at profile/purges[$purge_index]";
        }
        if ( exists $purge_ref->{maxdepth} && ( !defined $purge_ref->{maxdepth} || $purge_ref->{maxdepth} !~ /^\d+$/ ) )
        {
            LOGDIE "Invalid maxdepth (must be a number) at profile/purges[$purge_index]";
        }
        if ( $purge_ref->{action} eq 'rename_with_date' && ( !exists $purge_ref->{rename_suffix} || ref $purge_ref->{rename_suffix} ) )
        {
            LOGDIE "Missing or invalid rename_suffix specification at profile/purges[$purge_index]";
        }
    }

    return;
}

sub execute_all_purges
{
    my ( $profile_ref, $dry_run ) = @_;

    my $success = 1;

    foreach my $purge_ref ( @{ $profile_ref->{purges} } )
    {
        my %depth_spec = (
            depth    => 0, 
            mindepth => ( exists $purge_ref->{mindepth} ? $purge_ref->{mindepth} : $DEFAULT_MIN_DEPTH ),
            maxdepth => ( exists $purge_ref->{maxdepth} ? $purge_ref->{maxdepth} : $DEFAULT_MAX_DEPTH ),
        );

        if ( !execute_purge( $purge_ref, $dry_run, \%depth_spec ) )
        {
            $success = 0;
        }
    }

    return $success;
}

sub execute_purge
{
    my ( $purge_ref, $dry_run, $depth_spec_ref ) = @_;

    my $description = $purge_ref->{description};
    my @paths = @{ $purge_ref->{paths} };

    if ( !@paths )
    {
        INFO "Running purge '$description': no paths specified";
        return 0;
    }

    my %results = ( errors => 0 );
    foreach my $path ( @paths )
    {
        if ( -e filespec_encode( $path ) )
        {
            INFO "Running purge '$description' for path $path";
            purge_fs_object( $purge_ref, \%results, $dry_run, $path, $depth_spec_ref );
        }
        else
        {
            INFO "Running purge '$description': path '$path' does not exist";
        }
    }

    DEBUG "Purge '$description' produced $results{errors} errors";
    return !$results{errors};
}

sub purge_fs_object
{
    my ( $purge_ref, $results_ref, $dry_run, $path, $depth_spec_ref ) = @_;
    
    if ( depth_matches( $path, $depth_spec_ref )
      && matches_all_predicates( $path, $purge_ref->{predicates} ) )
    {
        perform_action( $purge_ref, $results_ref, $dry_run, $path );
    }
    
    if ( $depth_spec_ref->{depth} < $depth_spec_ref->{maxdepth}
      && -d filespec_encode( $path ) )
    {
        DEBUG "Recursing in $path";
        local $depth_spec_ref->{depth} = $depth_spec_ref->{depth} + 1;

        my $dirfh;
        if ( !opendir $dirfh, filespec_encode( $path ) )
        {
            ERROR "Unable to list the contents of directory $path: $OS_ERROR";
            $results_ref->{errors}++;
            return;
        }

        ENTRY: while ( my $dir_entry = readdir $dirfh )
        {
            $dir_entry = filespec_decode( $dir_entry );
            next ENTRY if $dir_entry =~ /^\.{1,2}$/;

            my $sub_path = File::Spec->catfile( $path, $dir_entry );
            purge_fs_object( $purge_ref, $results_ref, $dry_run, $sub_path, $depth_spec_ref );
        }
    }

    return;
}

sub depth_matches
{
    my ( $path, $depth_spec_ref ) = @_;

    if ( $depth_spec_ref->{depth} > $depth_spec_ref->{maxdepth} )
    {
        DEBUG "$path is too deep ($depth_spec_ref->{depth} >= $depth_spec_ref->{maxdepth})";
        return;
    }
    elsif ( $depth_spec_ref->{depth} < $depth_spec_ref->{mindepth} )
    {
        DEBUG "$path is too shallow ($depth_spec_ref->{depth} <= $depth_spec_ref->{mindepth})";
        return;
    }
    else
    {
        return 1;
    }
}

sub matches_all_predicates
{
    my ( $filename, $predicates_ref ) = @_;
    my $matches = 1;

    my ( $volume, $directory, $basename ) = File::Spec->splitpath( $filename );
    DEBUG "Considering $filename ($volume, $directory, $basename)";

    if ( ! -e filespec_encode( $filename ) )
    {
        ERROR "$filename does not exist";
        return;
    }

    foreach my $predicate_ref ( @$predicates_ref )
    {
        keys %$predicate_ref; # Reset "each"
        my ( $pred_name, $pred_value ) = each %$predicate_ref;

        if ( $pred_name =~ /^(i?)name$/ )
        {
            $matches = 0 if !matches_name( $pred_name, $pred_value, $filename, $basename, $1 eq 'i' );
        }
        elsif ( $pred_name =~ /^(i?)regex$/ )
        {
            $matches = 0 if !matches_regex( $pred_name, $pred_value, $filename, $1 eq 'i' );
        }
        elsif ( $pred_name eq 'mtime' || $pred_name eq 'mmin' )
        {
            $matches = 0 if !matches_mtime( $pred_name, $pred_value, $filename );
        }
        elsif ( $pred_name eq 'type' )
        {
            $matches = 0 if !matches_type( $pred_name, $pred_value, $filename );
        }
        elsif ( $pred_name eq 'empty' )
        {
            $matches = 0 if !matches_empty( $pred_name, $pred_value, $filename );
        }
        else
        {
            ERROR "Unknown predicate $pred_name, assuming no match";
            $matches = 0;
        }

        last if !$matches;
    }

    DEBUG "$filename matches all predicates? ", $matches ? 'yes' : 'no';
    return $matches;
}

sub perform_action
{
    my ( $purge_ref, $results_ref, $dry_run, $filename ) = @_;
    TRACE "perform_action( $purge_ref, $results_ref, $dry_run, $filename )";
    TRACE "perform_action: action=$purge_ref->{action}";

    my $ok = 0;
    if ( $dry_run )
    {
        $ok = action_dry_run( $filename, $purge_ref );
    }
    elsif ( $purge_ref->{action} eq 'delete' )
    {
        $ok = action_delete( $filename, $purge_ref );
    }
    elsif ( $purge_ref->{action} eq 'gzip' )
    {
        $ok = action_compress( $filename, $purge_ref );
    }
    elsif ( $purge_ref->{action} eq 'rename_with_date' )
    {
        $ok = action_rename_with_date( $filename, $purge_ref );
    }
    else
    {
        ERROR "Unknown action $purge_ref->{action}";
    }

    if ( !$ok )
    {
        TRACE "perform_action: not ok";
        ++$results_ref->{errors};
    }
    else
    {
        TRACE "perform_action: ok";
    }

    return;
}

sub matches_name
{
    my ( $pred_name, $pred_value, $filename, $basename, $case_insensitive ) = @_;

    my $regex = ( $case_insensitive ? '(?i)' : q{} ) . fileglob_to_re( $pred_value );
    if ( $basename =~ /$regex/ )
    {
        DEBUG "$filename matches $pred_name glob $pred_value";
        return 1;
    }
    else
    {
        DEBUG "$filename does not match $pred_name glob $pred_value";
        return;
    }
}

sub matches_regex
{
    my ( $pred_name, $pred_value, $filename, $case_insensitive ) = @_;

    my $regex = ( $1 eq 'i' ? '(?i)' : q{} ) . $pred_value;
    if ( $filename =~ /$regex/ )
    {
        DEBUG "$filename matches $pred_name /$regex/";
        return 1;
    }
    else
    {
        DEBUG "$filename does not match $pred_name /$regex/";
        return;
    }
}

sub matches_mtime
{
    my ( $pred_name, $pred_value, $filename ) = @_;

    my $mtime;
    if ( $pred_name eq 'mtime' )
    {
        $mtime = sprintf '%d', -M filespec_encode( $filename );
    }
    elsif ( $pred_name eq 'mmin' )
    {
        $mtime = sprintf '%d', ( -M filespec_encode( $filename ) ) * 24*60;
    }
    else
    {
        LOGDIE "Internal error: matches_mtime called with unknown predicate name";
    }


    if ( numeric_predicate_matches( $pred_value, $mtime ) )
    {
        DEBUG "$filename matches $pred_name $pred_value (file $pred_name is $mtime)";
        return 1;
    }
    else
    {
        DEBUG "$filename does not match $pred_name $pred_value (file $pred_name is $mtime)";
        return;
    }
}

sub numeric_predicate_matches
{
    my ( $pred_value, $number ) = @_;

    if ( $pred_value =~ /^\+(\d+)$/ )
    {
        return ( $number > $1 );
    }
    elsif ( $pred_value =~ /^-(\d+)$/ )
    {
        return ( $number < $1 );
    }
    elsif ( $pred_value =~ /^\d+$/ )
    {
        return ( $number == $pred_value );
    }
    else
    {
        ERROR "Invalid numeric predicate format: $pred_value";
        return;
    }
}

sub matches_type
{
    my ( $pred_name, $pred_value, $filename ) = @_;

    if ( ( $pred_value eq 'f' && -f filespec_encode( $filename ) )
      || ( $pred_value eq 'd' && -d filespec_encode( $filename ) ) )
    {
        DEBUG "$filename matches type $pred_value";
        return 1;
    }
    else
    {
        DEBUG "$filename does not match type $pred_value";
        return;
    }
}

sub matches_empty
{
    my ( $pred_name, $pred_value, $filename ) = @_;

    if ( -f filespec_encode( $filename ) && -z filespec_encode( $filename ) )
    {
        DEBUG "$filename is an empty file, matches";
        return 1;
    }
    elsif ( is_empty_dir( $filename ) )
    {
        DEBUG "$filename is an empty dir, matches";
        return 1;
    }
    else
    {
        DEBUG "$filename is not empty";
        return;
    }
}

# Transforms a shell-like glob to a regex for perl processing
# Adapted from Perl's find2perl
sub fileglob_to_re
{
    my ( $glob ) = @_;

    my $regex = $glob;
    $regex =~ s#([./^\$()+{}])#\\$1#g;
    $regex =~ s#\*#.*#g;
    $regex =~ s#\?#.#g;
    $regex = "\\A$regex\\z";

    DEBUG "Glob {$glob} -> Regexp /$regex/";
    return $regex
}

# Generates an INFO message on every file that would be processed
sub action_dry_run
{
    my ( $filename, $purge_ref ) = @_;

    my $action = $purge_ref->{action};
    INFO "Would $action: $filename";

    return 1;
}

# Deletes $filename (file or directory), reporting errors.
# Returns 1 if OK, !1 if at least one file failed to delete.
sub action_delete
{
    my ( $filename, $purge_ref ) = @_;

    rmtree( filespec_encode( $filename ), { result => \my $deleted_ref, error => \my $errors_ref } );
    foreach my $path ( @$deleted_ref )
    {
        $path = filespec_decode( $path );
        INFO "Deleted $path";
    }

    foreach my $error_ref ( @$errors_ref )
    {
        my ( $path, $message ) = each %$error_ref;
        $path = filespec_decode( $path );
        ERROR "Error deleting $path: $message";
    }

    my $error_count = @$errors_ref;
    if ( $error_count )
    {
        DEBUG "rmtree met $error_count errors";
        return;
    }
    else
    {
        return 1;
    }
}

# Wrapper around File::Path::rmtree that provides File::Path v2 behavior
sub rmtree
{
    if ( eval { File::Path->VERSION( 2 ); 1 } )
    {
        File::Path::rmtree( @_ );
    }
    else
    {
        my ( $filename, $status_ref ) = @_;

        DEBUG "Working around your legacy File::Path module (version 2.x is strongly preferred)";
        my $tempfile = File::Temp::tempfile();
        my $stdout = select $tempfile; # Redirect print calls from File::Path to $tempfile
        my $status = eval { File::Path::rmtree( $filename, 1 ) };
        my $error_string = $EVAL_ERROR;
        select $stdout; # Restore print behaviour

        seek $tempfile, 0, 0;
        ${ $status_ref->{result} } = [ map { chomp; s/^\w+//; $_ } readline $tempfile ];
        ${ $status_ref->{error} } = [];

        if ( !defined $status )
        {
            $error_string ||= "Other file deletion error, see standard error output for more info";
            ${ $status_ref->{error} } = [ $error_string ];
        }
    }

    return;
}

# Compresses $filename then deletes it
# Returns 1 if OK, !1 if compression or deletion failed
# Failing compression prevents deletion, but failing deletion doesn't revert
# compression because it would cause data loss in the case of a half-deleted
# input directory.
# Compressed files are not recompressed.
# Gzip compression does not allow input directories
sub action_compress
{
    my ( $filename, $purge_ref ) = @_;

    my $metadata_ref = read_file_metadata( $filename );
    my $error;
    my $encoded_filename = filespec_encode( $filename );
    if ( $purge_ref->{action} eq 'gzip' )
    {
        DEBUG "Running gzip compression on $filename";
        if ( -e filespec_encode( "$filename.gz" ) )
        {
            $error = "$filename.gz already exists";
        }
        elsif ( $filename =~ /\.gz$/ )
        {
            DEBUG "$filename is already compressed";
            return 1; # Do not proceed to deletion
        }
        elsif ( my $gz_error = gzip_file( $encoded_filename ) )
        {
            $error = $gz_error;
        }
        elsif ( $metadata_ref )
        {
            set_file_metadata( "$filename.gz", $metadata_ref );
        }
    }
    else
    {
        ERROR "Unknown compression method $purge_ref->{action}";
        return;
    }

    if ( $error )
    {
        ERROR "Error compressing $filename: $error";
        return;
    }
    else
    {
        INFO "Compressed $filename, deleting";
        return action_delete( $filename, $purge_ref );
    }
}

sub gzip_file_iocompress
{
    my ( $file ) = @_;

    if ( !IO::Compress::Gzip::gzip( $file, "$file.gz", BinModeIn => 1 ) )
    {
        no warnings 'once';
        return ( $IO::Compress::Gzip::GzipError || 'unknown error' );
    }
    else
    {
        return;
    }
}

sub gzip_file_cmd
{
    my ( $file ) = @_;

    open my $infd,   '<', '/dev/null' or LOGDIE "Can't open /dev/null: $OS_ERROR";
    open my $readfd, '>', '/dev/null' or LOGDIE "Can't open /dev/null: $OS_ERROR";

    # open3 doesn't accept lexically-managed filehandles :(
    my $pid = eval { open3( $infd, $readfd, \*GZERR, $GZIP_CMD, $file ); };
    if ( !$pid )
    {
        return $EVAL_ERROR;
    }

    my $errors = '';
    my $errchunk;
    while ( sysread GZERR, $errchunk, 1024 )
    {
        $errors .= $errchunk;
    }
    close GZERR or LOGDIE "Error closing gzip's error output: $OS_ERROR";
    $errors = filespec_decode( $errors );
    # Hopefully when sysread returns 0 (EOF), gzip finished

    ( waitpid $pid, 0 ) > 0
        or ERROR "unable to wait for gzip's dead process: $OS_ERROR";

    if ( $CHILD_ERROR )
    {
        my $signal = $CHILD_ERROR & 127;
        my $exitv  = $CHILD_ERROR >> 8;
        return "gzip error: ${errors}gzip exited with code $exitv / signal $signal";
    }

    if ( $errors )
    {
        WARN "gzip: $errors";
    }

    return;
}

sub select_gzip_alternative
{
    if ( eval { require IO::Compress::Gzip; } )
    {
        DEBUG "Selected IO::Compress:Gzip as the gzip compression method";
        *gzip_file = *gzip_file_iocompress;
    }
    else
    {
        DEBUG "IO::Compress::Gzip inclusion returned: $EVAL_ERROR, falling back to gzip command";
        if ( -x $GZIP_CMD )
        {
            DEBUG "Selected the external gzip command as the gzip compression method";
            *gzip_file = *gzip_file_cmd;
        }
        else
        {
            ERROR "$GZIP_CMD not found";
            LOGDIE "No suitable compression method found on this system";
        }
    }
}
# Call this at compile-time to pull IO::Compress::Gzip in the PAR package
BEGIN { select_gzip_alternative; }

sub read_file_metadata
{
    my ( $reference_file ) = @_;

    if ( my $stat_ref = File::stat::stat( filespec_encode( $reference_file ) ) )
    {
        return { stat => $stat_ref };
    }
    else
    {
        WARN "Cannot stat $reference_file ($OS_ERROR), metadata will not be restored";
        return;
    }
}

sub set_file_metadata
{
    my ( $filename, $metadata_ref ) = @_;

    DEBUG "Setting metadata on file $filename";

    my $error;
    if ( !utime $metadata_ref->{stat}->atime(), $metadata_ref->{stat}->mtime(), filespec_encode( $filename ) )
    {
        WARN "Unable to set atime and mtime on $filename ($OS_ERROR)";
        $error = 1;
    }

    if ( !chmod $metadata_ref->{stat}->mode() & 07777, filespec_encode( $filename ) )
    {
        WARN "Unable to set mode on $filename ($OS_ERROR)";
        $error = 1;
    }

    if ( !chown $metadata_ref->{stat}->uid(), $metadata_ref->{stat}->gid(), filespec_encode( $filename ) )
    {
        WARN "Unable to set uid/gid on $filename ($OS_ERROR)";
        $error = 1;
    }

    return !$error;
}

sub action_rename_with_date
{
    my ( $filename, $purge_ref ) = @_;
    TRACE "action_rename_with_date( $filename, $purge_ref )";

    TRACE "action_rename_with_date: preparing suffix with format $purge_ref->{rename_suffix}";
    my $suffix = datetime_now()->strftime( $purge_ref->{rename_suffix} );
    $suffix =~ tr/://d;
    my $target = "$filename$suffix";
    DEBUG "Renaming $filename to $target";
    my $error;

    if ( -e filespec_encode( $target ) )
    {
        $error = "$target already exists";
    }
    elsif ( !File::Copy::move( filespec_encode( $filename ), filespec_encode( $target ) ) )
    {
        $error = $OS_ERROR ? "$OS_ERROR" : "unknown error";
        unlink filespec_encode( $target );
    }

    if ( $error )
    {
        ERROR "Failed renaming $filename to $target: $error";
        return;
    }
    else
    {
        INFO "Renamed $filename to $target";
        return 1;
    }
}

# Memoized (one timestamp per purge-any run)
sub datetime_now
{
    TRACE "datetime_now()";
    TRACE "NB: if purge-any.exe (not .pl) stops here, you are most likely missing a local timezone. Try adding more DateTime::TimeZone classes and repackage.";
    my $now_ref = DateTime->now( time_zone => 'local' );
    TRACE "DateTime->now() OK";
    return $now_ref;
}
# Call this once at compile-time to pull in all the required timezone dependencies
# (such as Win32 registry access)
BEGIN { datetime_now(); }

# Figure out the name of the encoding to use to match the current locale
# (on POSIX hosts at least)
sub get_locale_encoding
{
    my $encoding;
    if ( $OSNAME eq 'MSWin32' )
    {
        $encoding = get_win32_encoding();
        INFO "Assuming the system encoding to be $encoding (from Win32's codepage)";
    }
    elsif ( defined &encoding::_get_locale_encoding )
    {
        $encoding = encoding::_get_locale_encoding();
        INFO "Assuming the system encoding to be $encoding (from Perl)";
    }
    else
    {
        no warnings 'uninitialized';
        my $env_encoding = $ENV{'LC_ALL'} || $ENV{'LC_CTYPE'} || $ENV{'LANG'};
        if ( $env_encoding =~ /\butf-?8\b/i )
        {
            $encoding = 'utf8';
            INFO "Assuming the system encoding to be $encoding (from POSIX environnement variables)";
        }
    }
    
    if ( !$encoding )
    {
        WARN "Local encoding not known, file names with non-ASCII characters may not work (assuming utf8)!";
        $encoding = 'utf8';
    }

    return $encoding;
}

sub get_win32_encoding
{
    # Emulates what the defunct Win32::Codepage did
    my $codepage = Win32::Codepage::Simple::get_acp()
        || Win32::Codepage::Simple::get_oemcp();
    return unless $codepage && $codepage =~ m/^[0-9a-fA-F]+$/s;
    return "cp".lc($codepage);
}

# Converts an internal Perl string to a byte string compatible with this
# platform.
sub filespec_encode
{
    my ( $filespec ) = @_;
    return Encode::encode( get_locale_encoding(), $filespec );
}

# Converts a byte string returned by the OS' raw API calls to an internal Perl
# string.
sub filespec_decode
{
    my ( $filespec ) = @_;
    return Encode::decode( get_locale_encoding(), $filespec );
}

# Returns 1 if $filename is a directory and is empty.
sub is_empty_dir
{
    my ( $filename ) = @_;

    if ( !-d filespec_encode( $filename ) )
    {
        return;
    }

    opendir my $directory, filespec_encode( $filename );
    while ( my $content = readdir $directory )
    {
        if ( $content =~ /^\.\.?$/ )
        {
            # Skip . and ..
        }
        else
        {
            return; # There is something else, so it's not empty
        }
    }

    return 1; # There was nothing in the directory
}


=head1 NAME

purge-any.pl - Generic file purging tool

=head1 DESCRIPTION

purge-any is a schedulable, cross-platform tool for purging files with a single,
structured configuration. This configuration contains several profiles,
one per host, and can therefore be replicated safely accross all servers.


=head1 VERSION

This documentation refers to purge-any version 1.013.

=head1 USAGE

  purge-any.pl [options] [--show-config|--dry-run]
  purge-any.pl --help
  purge-any.pl --man
  purge-any.pl --version

=head1 OPTIONS

=over

=item C<< --config-file|-f <file> >>

Specifies a different configuration file. Default: C<purge-any.conf> in the
current directory.

=item C<< --profile|-p <profile> >>

The profile name to use as a purge specification. By default, the
host name in lower case is used.

=item C<< --show-config >>

Displays which configuration file and profile are used.

=item C<< --dry-run >>

Shows which actions would be taken, but do not alter anything.

=item C<< --verbose|-v >>

Increases the verbosity level (by default, only messages of ERROR level and
above are displayed). This option can be specified multiple times. Logging
levels: FATAL - ERROR - WARN (-v) - INFO (-vv) - DEBUG (-vvv) - TRACE (-vvvv).


=back

=head1 CONFIGURATION EXAMPLE

See below for a thorough explanation of how the configuration file is
structured, its syntax and semantics. For the impatient, here is a commented
example of configuration file demonstrating most of purge-any's features.

  --- 
  logging: 
      # On GNU/Linux, log errors and fatal messages to the console
      linux: |
        log4perl.rootLogger = ERROR, Screen
        log4perl.appender.Screen = Log::Log4perl::Appender::Screen
        log4perl.appender.Screen.layout = Log::Log4perl::Layout::SimpleLayout

      # On MS Windows, log errors and fatal messages in UTF8 format to
      # "purge-any.log" in the current directory.
      MSWin32: |
        log4perl.rootLogger = ERROR, File
        log4perl.appender.File = Log::Log4perl::Appender::File
        log4perl.appender.File.filename = purge-any.log
        log4perl.appender.File.utf8 = 1
        log4perl.appender.File.layout = Log::Log4perl::Layout::SimpleLayout

  profiles:
      # The "hera" profile will be the default on HERA
      hera:
          purges:
              # First purge specification. Notice the leading "-", as this is a
              # list of purges!
              -   description: 'Purge old integration files'
                  # Look for files to purge in the following list recursively
                  paths:
                      - 'W:\Organisation\Informatique\PhotoIntegVentes\Belgique'
                      - 'W:\Organisation\Informatique\PhotoIntegVentes\Espagne'
                      - 'W:\Organisation\Informatique\PhotoIntegVentes\France'
                      - 'W:\Organisation\Informatique\PhotoIntegVentes\Italie'
                  # The files must be named in a given way and not have been
                  # modified for more than 30 days.
                  predicates:
                      - name: 'PhotoIntegVentes_*.csv'
                      - mtime: +30
                  # Delete those
                  action: delete

              # Another purge, it will be executed after the first one
              -   description: Another purge
                  ...



=head1 CONFIGURATION REFERENCE

=head2 Configuration File Structure

The configuration is a single file in YAML format (see below, L</YAML Primer>),
structured like this:

=over

=item *

B<logging> -- logging configuration in L<Log::Log4perl> format (similar to
log4j).

=over

=item *

B<linux> -- logging configuration for GNU/Linux hosts

=item *

B<MSWin32> -- logging configuration for MS Windows hosts

=back

=item *

B<profiles>

=over

=item *

B<< <profile name> >> -- usually named after the host, but a different name can
be used for specific set of purges that must be called by name (usually C<<
<host>_<name> >>).

=over

=item *

B<purges> -- contains a list of purge specifications (see below)

=back

=back

=back



=head2 Purge Specification

The B<purges> entry contains a list of purge specifications that will be
executed in the order they appear in the configuration file. Each of them is
structured like this:

=over

=item *

B<description> -- A short description of the purge aimed at humans that will
appear in the log file. It should be unique (it's easier to analyze log files
when it is).

=item *

B<paths> -- A list of file system paths on which this purge shall be applied.
By default, the file system objects specified in B<paths> are not purged, only
their contents.

=item *

B<predicates> -- A list of L<predicates|/Predicates> (conditions) that will be tested on all
file system objects (files, directories, ...) under B<paths>. If all of them
match, then B<action> will be taken.

NB: This means that expressing C<OR> conditions (such as delete all files
called C<*.old> or older than 30 days) requires multiple purge specification
entries.

The available predicates are detailed below.

The B<predicates> key can be omitted if empty (ie. delete anything under
B<paths>).

=item *

B<mindepth> -- The minimum file system hierarchy depth that must be reached
before purging. The default value is C<1>, ie. the specified B<paths> will not be
purged. Example:

  description: 'Delete a given file'
  paths:
    - /tmp/somefile
  mindepth: 0
  action: delete

=item *

B<maxdepth> -- The maximum file system hierarchy depth that will be considered
for purging. The default is C<1024>, which should be more than the OS limit,
while still preventing infinite recursion in unforeseen file system accidents.
Example:

  description: 'Delete all files under /some/dir but not under /some/dir/subdir'
  paths:
    - /some/dir
  predicates:
    - type: f
  maxdepth: 1
  action: delete


=item *

B<action> -- The L<action|/Actions> to take on the file system objects that match
B<predicates>. Currently, C<delete>, C<rename_with_date> and C<gzip> are implemented.

=back



=head2 Predicates

A predicate tests a specific property of a file system object. Purge-any's
predicates are mostly a subset of GNU find's (so, if you already know Unix or
GNU, you've got a head start). Currently, the following are implemented:

=head3 B<name>

B<name> matches the file system object name (not the complete path) with a
glob pattern. The usual shell wildcards are implemented:

=over

=item *

C<*> matches zero or more characters

=item *

C<?> matches exactly one character

=item *

C<[AB-E]> matches any single character C<A> or between C<B> and C<E> inclusive.

=item *

C<[^AB-E]> matches any single character I<except> C<A> or those between C<B>
and C<E> inclusive.

=back

Examples:

=over

=item *

C<*.old> -- match any file with a C<.old> extension (but not C<.Old> or C<.OLD>)

=item *

C<200[89]-??-?? *> -- match any file presumably named after a 2008 or 2009
date, such as C<2008-12-24 merry xmas.txt>.

=back



=head3 B<iname>

B<iname> works just like B<name>, but in a case-insensitive way. Ie, C<*.old>
will match C<file.OLD> as well.


=head3 B<regex>

Tries to match the given regular expression on the I<whole path> (unlike
B<name>, which matches the file system object only). Documenting regular
expressions is outside the scope of this document, but there are plenty good
introductions available on the Internet (see L<perlre> for a complete
reference).

NB: This regular expression is not anchored, so one must use C<^> and/or C<$>
to match respectively the start and end of the path.

Examples:

=over

=item *

C<\.old$> -- match any file with a C<.old> extension (but not C<.Old> or C<.OLD>)

=item *

C<\\Dossiers? techniques?\\(0.|201.)H\\> -- match everything under the winter
seasons of C-Design's C<Dossiers techniques> (plural or singular). Examples:
C<Archives C-design\Dossiers techniques\2010H\Okaidi>, C<Archives C-design
JAC\Dossier technique\08H\Layettes>.

=back

=head3 B<iregex>

B<iname> works just like B<regex>, but in a case-insensitive way.



=head3 B<mtime>

B<mtime> matches only if the last modification time of the file system object
is less than, equal to or greater than a given value.

The last modification time is expressed in whole days since the start of
purge-any. Like in find(1), the decimal part is dropped and not rounded.

Examples:

=over

=item *

C<+30> -- matches all files not modified in the last 30 days.

=item *

C<-30> -- matches all files that were modified in the last 30 days.

=item *

C<0> -- matches all files last modified in the past 24 hours.

=back



=head3 B<mmin>

B<mmin> works exactly like B<mtime>, but in minute rather than day units, eg.
C<+60> will match all files not modified in the last hour.



=head3 B<type>

B<type> matches only if the following file system object is of the given type.
Currently implemented : B<f>ile, B<d>irectory.

Example:

  description: 'Delete all files under /some/directory'
  paths:
    - /some/directory
  predicates:
    - type: f
  action: delete

=head3 B<empty>

B<empty> matches only files with zero size or directories with no content. In
the configuration file, the only supported value for this predicate is B<yes>.

  description: 'HRPRD $SIGACS/archives (operations)'
  paths:
      - '/u01/app/hraccess/HRPRD/archives'
  predicates:
      - type: d
      - empty: yes
  action: delete



=head2 Actions

=head3 C<delete>

Delete matching files and directories.


=head3 C<rename_with_date>

Rename the matching files and directories, adding a date-based suffix.

The suffix is given in the companion C<rename_suffix> purge specification
attribute. Its syntax follows L<DateTime/strftime Patterns> (pretty close to
POSIX' C<strftime(2)>). Here are the most common escape sequences and some
examples:

=over

=item *

B<%{datetime}> - the nearly ISO8601-compatible date and time (example:
C<2011-01-28T160152>). This is the same as C<%FT%T>.

=item *

B<%F> - the full date in a sortable format (example: C<2011-01-28>). This is
the same as C<%Y-%m-%d>.

=item *

B<%T> - the full time in a sortable format (example: C<160152>). This is the
same as C<%H%M%S>.

=back

Note: the real ISO8601 and C<%T> formats use the colon (C<:>) as time separator
(example: C<2011-01-28T16:01:52>), but MS Windows does not allow colons in
filenames. Therefore, this character is removed from all resulting dates (even
on *nix).

Example:

  description: 'Rotate cmd.log to eg. cmd.log.2011-01-28 (run once a day)'
  paths:
      - 'E:\Interfaces\CMD_IN\LOG'
  predicates:
      - name: 'cmd.log'
  action: rename_with_date
  rename_suffix: '.%F'



=head3 C<gzip>

Compress matching files to C<< <filename>.gz >>. Notes:

=over

=item *

This format does not support directories, which are thus left untouched and
reported as errors.

=item *

Existing C<< <filename>.gz >> archives are not overwritten, instead the
matching file is skipped and reported in error.

=item *

Filenames ending in C<.gz> are supposed to be already compressed and are
silently skipped (this allows running a gzip purge multiple times on directory
contents without ending with C<foo.gz.gz.gz.gz> files).

=item *

File C<atime>, C<mtime>, mode, owner and group are replicated from the matching
file to the archive. Owner and group are skipped if running as non-root, and
only the first two are relevant on MSWin32 platforms.

=back

Example:

  description: 'Compress Oracle archives untouched in the last day'
  paths:
      - '/u03/oradata/arch'
  predicates:
      - type: f
      - mtime: +0
  action: gzip



=head2 YAML Primer

The configuration file is written in YAML (L<http://www.yaml.org>), a
human-friendly format that can store arbitrary computer data structures.

Indentation matters in YAML, so if the first element of a list starts with 4
leading spaces, the next elements must have the same 4 leading spaces, and any
sub-structure will have to be indented with more than 4 leading spaces.

Here are the basic building blocks what one needs to know to work with
purge-any configuration files:

=head3 Lists

A list is an ordered collection of items (which may be themselves complex data
structures).

In YAML, the elements are written one per line with a leading C<-> sign.

Example:

  - /u01
  - /u02

=head3 Dictionaries

A dictionary (aka. hash) is a set of key-value pairs, where the keys must be
unique and the order is irrelevant.

In YAML, they are written in the form C<<
<key>: <value> >>, one per line. Either part can be quoted if necessary, and
C<< <value> >> may be itself a complex data structure.

Example:

  description: 'Some description'
  paths:
      - /u01
      - /u02

=head3 Quoted Strings

Simple texts can exist in YAML without further precaution. However, some
symbols are special meanings (C<< -?:,[]{}#&*!|'">%@` >>), so when in doubt it's
safer to put text between single (C<'>) or double (C<">) quotes. Example:

  /u01

Single-quoted strings (C<'abc'>) are the simplest, as all characters between
these delimiters have no special meaning except C<'> itself. C<'> inside a
single-quoted string can be expressed by doubling it, like in SQL. Example:

  'It''s a wonderful world!'

Double-quoted strings accept several escapes introduced by a backslash, similar
to strings in C:

  "line1\nline2\nIt's still a wonderful \"world\"!"

On the topic of multi-line strings (such as the logging configuration), the
easiest way to express them is to start with a pipe character (C<|>) and to end
the block with a blank line or a lesser indented line. Examples:

  |
  line1
  line2
  It's still a wonderful "world"!
  <blank line>

and

  logging: |
      log4perl.rootLogger = ERROR, Screen
      ...
  profiles:

=head3 Comments

Lines starting with a C<#> are comments and ignored by YAML.



=head1 DIFFERENCES FROM GNU FIND

Purge-any aims to be as compatible as possible with GNU find (this is easier to
learn), however for practical reasons or to match intuitive behavior it
displays the following differences:

=over

=item *

The B<regex>/B<iregex> predicates are not anchored, so one must use C<^> and/or
C<$> to match respectively the start and end of the path.

=item *

The B<mindepth> setting defaults to 1, not 0. This means that the specified
B<paths> are not purged unless it is explicitely set to 0.

=back




=head1 REQUIREMENTS

=over

=item *

Perl 5.8.8 or higher.

=item *

C<Log::Log4perl>.

=item *

C<YAML::XS> (also known as YAML::LibYAML, libyaml-libyaml-perl, ...).

=item *

C<DateTime> (and C<DateTime::Locale>, C<DateTime::TimeZone> when packaged
separately).

=item *

C<IO::Compress::Gzip> version 2 or higher, or GNU gzip(1) installed as
C</usr/bin/gzip>.

=item *

On MS Windows platforms: C<Win32::Codepage::Simple> and
C<DateTime::TimeZone::Local::Win32>.

=back



=head2 Installation on Redhat Enterprise Linux

=head3 RHEL4

Install the prerequisites RPMs found in rhel4/:

  rpm -ivh rhel4/*{noarch,i386}.rpm
  OR
  rpm -ivh rhel4/*{noarch,x86_64}.rpm

Then use the purge-any.pl script.

=head3 RHEL5 or RHEL6

Install the RPMs found in rhel5/ or rhel6/ respectively:

  yum localinstall rhelX/*{noarch,x86_64}.rpm

Since purge-any version 1.014, these RPMs include purge-any itself (it will be
installed in the PATH, C</usr/bin/purge-any>).


=head2 Installation on MS Windows

For MS Windows, I recommend to use a PAR-packaged C<.exe>.

It can be created by running the C<create_exe.sh> script on a workstation with
all the prerequisites installed through ActivePerl. You'll need the following
extra dependency: C<PAR::Packer>.

If you get the error C<Perl lib version (5.a.b) doesn't match executable
'perl.exe' version (5.a.c)>, the C<PAR::Packer> package provided by ActivePerl
was not compiled exactly for their Perl binary version (for example, they
compiled the package with Perl 5.20.1 but you downloaded ActivePerl 5.20.2).

The fix is to uninstall C<PAR::Packer>, install the C<mingw> and C<dmake>
packages from PPM, and recompile it yourself:

  set PATH=C:/Perl/site/lib/auto/MinGW/bin;%PATH%
  cpan install PAR::Packer

=head2 Installation on AIX 5.3

Install the prerequisites using the following commands (from the purge-any directory):

  set -o noclobber
  echo Europe/Paris >/etc/timezone
  rpm -ivh aix53/deps/*.rpm
  for f in aix53/deps/*.tar.gz; do gzip -dc $f |tar xf - ; done

The /etc/timezone is ignored by AIX, but is required by the DateTime library.

NB: if you need to handle files with non-ascii names (French accentuated
letters), your locale must be UTF-8-based. For example, run this command before
calling C<purge-any.pl>:

  export LC_CTYPE=FR_FR.UTF-8


=head2 Creating the AIX 5.3 binaries from the sources

Note: this is for documentation purposes only, it should not be required as
long as you have the provided C<aix53/deps> directory.

=head3 Installing the C compiler

Copy C<vacpp.10.1.0.0.aix.eval.tar.Z> in C</opt/app/sources>.

  mkdir xlcpp10
  cd xlcpp10
  uncompress -c ../vacpp.10.1.0.0.aix.eval.tar.Z |tar xf -
  installp -aYg -d usr/sys/inst.images -e /tmp/install2.log vac.C

The following packages will be installed:

  vac.C 10.1.0.0                              # IBM XL C Compiler
  memdbg.adt 5.4.0.0                          # User Heap/Memory Debug Toolkit
  memdbg.aix53.adt 5.4.0.0                    # User Heap/Memory Debug Toolk...
  vac.aix53.lib 10.1.0.0                      # XL C for AIX Libraries for A...
  vac.include 10.1.0.0                        # IBM XL C Compiler Include Files
  vac.lib 10.1.0.0                            # XL C for AIX Libraries
  vacpp.tnb 10.1.0.0                          # IBM XL C/C++ Evaluation Lice...
  xlmass.adt.include 5.0.0.0                  # IBM Mathematical Acceleratio...
  xlmass.aix53.lib 5.0.0.0                    # IBM Mathematical Acceleratio...
  xlmass.lib 5.0.0.0                          # IBM Mathematical Acceleratio...
  xlsmp.aix53.rte 1.8.0.0                     # SMP Runtime Libraries for AI...
  xlsmp.rte 1.8.0.0                           # SMP Runtime Library

=head3 Installing dependencies

  rpm -ivh aix53/deps/*.rpm

=head3 Compiling the Perl modules and their build dependencies

  export PATH=$PATH:/usr/vac/bin
  cd aix53/sources

  # Uncompress all sources
  for f in *.tar.gz; do gzip -cd $f |tar xf -; done

  # Install build dependencies
  for dir in ExtUtils-CBuilder-0.27 ExtUtils-ParseXS-2.22 Module-Build-0.36; do
    ( cd $dir; perl Makefile.PL; make test && make install )
  done >build-deps.log 2>&1

  # Installing dependencies (Makefile.PL build system)
  for dir in Class-Singleton-1.4 Compress-Raw-Bzip2-2.033 Compress-Raw-Zlib-2.033 IO-Compress-2.030 List-MoreUtils-0.26 Log-Log4perl-1.26 YAML-LibYAML-0.32; do
    ( cd $dir; perl Makefile.PL; make test && make install );
  done >build-mkf.log 2>&1

  # Installing dependencies (Build.PL build system)
  for dir in Params-Validate-0.95 DateTime-Locale-0.45 DateTime-TimeZone-0.91 DateTime-0.53; do
    ( cd $dir; perl Build.PL; ./Build && ./Build install )
  done >build-mb.log 2>&1

  # Packaging the final result
  cp /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/Class/Singleton/.packlist        Class-Singleton-1.4-aix53.packlist
  echo /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/Class/Singleton/.packlist    >>Class-Singleton-1.4-aix53.packlist
  cp /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/Compress/Raw/Bzip2/.packlist     Compress-Raw-Bzip2-2.033-aix53.packlist
  echo /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/Compress/Raw/Bzip2/.packlist >>Compress-Raw-Bzip2-2.033-aix53.packlist
  cp /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/Compress/Raw/Zlib/.packlist      Compress-Raw-Zlib-2.033-aix53.packlist
  echo /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/Compress/Raw/Zlib/.packlist  >>Compress-Raw-Zlib-2.033-aix53.packlist
  cp /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/DateTime/.packlist               DateTime-0.53-aix53.packlist
  echo /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/DateTime/.packlist           >>DateTime-0.53-aix53.packlist
  cp /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/DateTime/Locale/.packlist        DateTime-Locale-0.45-aix53.packlist
  echo /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/DateTime/Locale/.packlist    >>DateTime-Locale-0.45-aix53.packlist
  cp /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/DateTime/TimeZone/.packlist      DateTime-TimeZone-0.91-aix53.packlist
  echo /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/DateTime/TimeZone/.packlist  >>DateTime-TimeZone-0.91-aix53.packlist
  cp /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/IO/Compress/.packlist            IO-Compress-2.030-aix53.packlist
  echo /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/IO/Compress/.packlist        >>IO-Compress-2.030-aix53.packlist
  cp /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/List/MoreUtils/.packlist         List-MoreUtils-0.26-aix53.packlist
  echo /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/List/MoreUtils/.packlist     >>List-MoreUtils-0.26-aix53.packlist
  cp /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/Log/Log4perl/.packlist           Log-Log4perl-1.26-aix53.packlist
  echo /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/Log/Log4perl/.packlist       >>Log-Log4perl-1.26-aix53.packlist
  cp /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/Params/Validate/.packlist        Params-Validate-0.95-aix53.packlist
  echo /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/Params/Validate/.packlist    >>Params-Validate-0.95-aix53.packlist
  cp /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/YAML/LibYAML/.packlist           YAML-LibYAML-0.32-aix53.packlist
  echo /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/YAML/LibYAML/.packlist       >>YAML-LibYAML-0.32-aix53.packlist
  for list in *.packlist; do tar -cf - -L $list |gzip -c >../deps/${list%.packlist}.tar.gz; done
  # Uninstalling all libs
  cat *.packlist \
    /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/ExtUtils/CBuilder/.packlist \
    /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/ExtUtils/ParseXS/.packlist \
    /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/auto/Module/Build/.packlist \
    |xargs rm

=head3 Uninstalling the compiler

  installp -u vac.C memdbg.adt memdbg.aix53.adt vac.aix53.lib vac.include vac.lib vacpp.tnb xlmass.adt.include xlmass.aix53.lib xlmass.lib xlsmp.aix53.rte xlsmp.rte



=head1 EXIT CODES

=over

=item *

0 -- OK (all files were purged as expected)

=item *

1 -- NOK (some files could not be purged, see the log for more details)

=item *

255 -- an error occured

=back



=head1 BUGS AND LIMITATIONS

=over

=item *

Escaping wildcards characters is not possible in glob patterns (but this
doesn't matter on MS Windows, as such files cannot exist there).

=item *

The predicates definition does not allow complex logic constructs and requires
multiplying the purge entries to express OR operators.

=item *

On Perl installations with File::Path version 1.x (such as RHEL4), this script
has to use a kludge to obtain a proper report of deleted files and errors may
not be reported correctly. Additionally, this workaround code has not been
thoroughly tested. In particular, there seems to be a file descriptor leak with
some versions of File::Temp.

=back


=head1 AUTHOR

Thomas Equeter <tequeter@users.noreply.github.com>


=head1 COPYRIGHT AND LICENCE

Copyright (C) 2010-2015, Idgroup.


=cut

