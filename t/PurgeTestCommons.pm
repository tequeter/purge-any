package PurgeTestCommons;

use strict;
use warnings;
our $VERSION = 0.001;
use English qw( -no_match_vars );
use Exporter qw( import );
use File::Temp;
use Test::More;
use Memoize;
use Encode;
if ( $OSNAME eq 'MSWin32' )
{
    require Win32::Codepage::Simple;
}
else
{
    require encoding; # For its utility function
}

our @EXPORT_OK = qw( touch xtempdir purge_any quote_win32_path filespec_encode filespec_decode );

sub touch
{
    my ( $date, @files ) = @_;

    foreach my $file ( @files )
    {
        if ( ! -e $file )
        {
            open my $fd, '>', $file or die "creat $file: $OS_ERROR";
        }
    }

    utime $date, $date, @files or die "utime: $OS_ERROR";

    return;
}

sub xtempdir
{
    my $dir = File::Temp::tempdir( 'purge-any-test-XXXXXX', TMPDIR => 1, CLEANUP => !$ENV{PURGE_TEST_DEBUG} );

    if ( $ENV{PURGE_TEST_DEBUG} )
    {
        diag( "Creating test directory $dir" )
    }

    return $dir;
}

sub purge_any
{
    my ( $conf, $profile, $extra_opts_ref, $replaces_ref ) = @_;

    push @$extra_opts_ref, '-vvv' if $ENV{PURGE_TEST_DEBUG};

    open my $template, '<:encoding(utf8)', "t/$conf" or die "Cannot open t/$conf: $OS_ERROR";
    my $contents = do { local $/; readline $template; };

    while ( my ( $var, $value ) = each %$replaces_ref )
    {
        $contents =~ s/$var/$value/g;
    }
    
    #open my $real_conf, '>', "$dir/$conf" or die "Cannot open $dir/$conf: $OS_ERROR";
    my ( $real_conf, $real_conf_name ) = File::Temp::tempfile( undef, UNLINK => 1 );
    binmode $real_conf, ':encoding(utf8)';
    print {$real_conf} $contents;
    close $real_conf;

    my $script = File::Spec->catfile( File::Spec->curdir(), "purge-any.pl" );
    my $result = system $script, '-f', $real_conf_name, '-p', $profile, @$extra_opts_ref;
    #diag( "purge-any.pl returned $result" );
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
        return !( $result >> 8 );
    }
}

sub quote_win32_path
{
    my ( $path ) = @_;
    $path =~ s/\\/\\\\/g;
    return $path;
}

sub get_win32_encoding
{
    # Emulates what the defunct Win32::Codepage did
    my $codepage = Win32::Codepage::Simple::get_acp()
        || Win32::Codepage::Simple::get_oemcp();
    return unless $codepage && $codepage =~ m/^[0-9a-fA-F]+$/s;
    return "cp".lc($codepage);
}

memoize( 'get_locale_encoding' );
sub get_locale_encoding
{
    my $encoding;
    if ( $OSNAME eq 'MSWin32' )
    {
        $encoding = get_win32_encoding();
    }
    elsif ( defined &encoding::_get_locale_encoding )
    {
        $encoding = encoding::_get_locale_encoding();
    }
    else
    {
        no warnings 'uninitialized';
        my $env_encoding = $ENV{'LC_ALL'} || $ENV{'LC_CTYPE'} || $ENV{'LANG'};
        if ( $env_encoding =~ /\butf-?8\b/i )
        {
            $encoding = 'utf8';
        }
    }
    
    if ( !$encoding )
    {
        warn "Local encoding not known, file names with non-ASCII characters may not work (assuming utf8)!";
        $encoding = 'utf8';
    }

    return $encoding;
}


sub filespec_encode
{
    my ( $filespec ) = @_;
    return Encode::encode( get_locale_encoding(), $filespec );
}

sub filespec_decode
{
    my ( $filespec ) = @_;
    return Encode::decode( get_locale_encoding(), $filespec );
}

1;

__END__

=head1 NAME

PurgeTestCommons - Common functions for purge-any.pl tests


=head1 INTERFACE

=head2 touch( $date, @files )

Like touch(1).

=head2 xtempdir()

Returns a temporary directory.

=head2 purge_any( $conf, $profile, $extra_opts_ref, $replaces_ref )

=head2 quote_win32_path

Escapes the backslashes for regex purposes

=head1 DIAGNOSTICS



=head1 CONFIGURATION AND ENVIRONMENT



=head1 BUGS AND LIMITATIONS

There are no known bugs in this module.
Please report problems to Thomas Equeter (waba)
Patches are welcome.

=head1 AUTHOR

Thomas Equeter (waba), <waba@waba.be>


=head1 LICENSE AND COPYRIGHT

Copyright (c) 2010 Thomas Equeter <waba@waba.be>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut


