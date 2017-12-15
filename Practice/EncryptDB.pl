use Modern::Perl;
use Encode;
use Crypt::CBC;
use Storable qw/freeze thaw store retrieve/;
use Data::Dump qw/dump/;
use File::Slurp;
use IO::Handle;
STDOUT->autoflush(1);

our $enc_file = "encrypt.db";
our $key = "password";
our $data = {};
our $stream;

say "Creating Data";
{
    my $ref = $data;
    for my $c ('a' .. 'f') 
    {
        $ref->{'info'} = ord($c);
        $ref->{$c} = {};
        $ref = $ref->{$c};
    }

    $stream = freeze( $data );
    say unpack "H*", $stream;
    #store $data, "PerlStruct.DB";
}

say "\nEncrypting\n";
{
    my $cipher = Crypt::CBC->new( -key => $key, -cipher => 'Blowfish' );
    my $ciphertext = $cipher->encrypt( $stream );
    write_file( $enc_file, { binmode => ":raw" }, $ciphertext );
}

say 'Decrypting';
{
    my $cipher = Crypt::CBC->new( -key => $key, -cipher => 'Blowfish' );
    my $ciphertext = read_file( $enc_file, binmode => ":raw" );
    my $plaintext  = $cipher->decrypt($ciphertext);
    dump thaw($plaintext);
}
