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
decrypt($password, "encrypt.db");
get_password();

sub get_password
{
    my @st;
    my $str = "";
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
        }
    }

    return $str;
}

# 退格处理
sub reduce
{

}

# sub encrypt
# {
#     my ($key) = shift;
#     say "\nEncrypting\n";
#     my $cipher = Crypt::CBC->new( -key => $key, -cipher => 'Blowfish' );
#     my $ciphertext = $cipher->encrypt( $stream );
#     write_file( $enc_file, { binmode => ":raw" }, $ciphertext );
# }

sub decrypt
{
    say "\nDecrypting\n";
    my ($key, $file) = @_;
    my $cipher = Crypt::CBC->new( -key => $key, -cipher => 'Blowfish' );
    my $ciphertext = read_file( $file, binmode => ":raw" );
    my $plaintext  = $cipher->decrypt($ciphertext);
    dump thaw($plaintext);
}
