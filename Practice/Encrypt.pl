use Modern::Perl;
use Encode;
use Crypt::CBC;
use IO::Handle;
use File::Slurp;
STDOUT->autoflush(1);

our $enc_file = "encrypt.txt";
our $key = "password";

Encrypt:
{
    my $cipher = Crypt::CBC->new( -key => $key, -cipher => 'Blowfish' );
    my $string = join("\n", 
                map {
                    join ("", map { ('A'..'Z')[rand(26)] } (1..79) )
                } (1..50) );

    my $ciphertext = $cipher->encrypt( $string );
    write_file( $enc_file, { binmode => ":raw" }, $ciphertext );
}

Decrypt:
{
    my $cipher = Crypt::CBC->new( -key => $key, -cipher => 'Blowfish' );
    
    my $ciphertext = read_file( $enc_file );
    my $plaintext  = $cipher->decrypt($ciphertext);
    say $plaintext;
}
