=info
    Author : PAKTC/PerlMonk
=cut

use Modern::Perl;
use Win32::Console;
use Crypt::CBC;
use File::Slurp;
use Storable qw/freeze thaw/;
use Time::HiRes qw/sleep/;
use Data::Dump qw/dump/;
use IO::Handle;
STDOUT->autoflush(1);

my $IN=Win32::Console->new(STD_INPUT_HANDLE);
my $OUT=Win32::Console->new(STD_OUTPUT_HANDLE);

my $IN_DEFAULT = $IN->Mode();
$IN->Mode(ENABLE_MOUSE_INPUT);

my $password = get_password();
my $data = read_file( "Notes.db", { binmode => ":raw" } );
$data = "HEAD". $data;
encrypt(\$data, $password);

write_file( "Notes_crypt.db", { binmode => ":raw" }, $data );

sub get_password
{
    my @st;
    my $str = "";
    print "Password:";

    while (1)
    {
        sleep 0.01;
        @st = $IN->Input();
        next if ($#st < 0);
        if ( $st[0] == 1 and $st[1] == 1 )
        {
            if ( chr($st[5]) =~ /[\x20-\x7e]/ ) { print "*"; $str .= chr($st[5]) }
            elsif ( $st[5] == 27 ) { exit }
            elsif ( $st[5] == 13 ) { last }
            elsif ( $st[5] == 8 )  { 
                if ( length($str) > 0 ) 
                {
                    print "\b \b";
                    $str=~s/.$//;
                }
            }
        }
    }
    return $str;
}

# 退格处理
sub reduce
{
}

sub encrypt
{
    say "\nEncrypting\n";
    my ($data_ref, $key) = @_;
    my $cipher = Crypt::CBC->new( -key => $key, -cipher => 'Blowfish' );
    $$data_ref = $cipher->encrypt( $$data_ref );
}
