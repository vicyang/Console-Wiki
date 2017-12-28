LOAD_AND_SAVE:
{
    sub load_data
    {
        my ($href, $file) = @_;
        if ( -e $file ) 
        {
            my $stream = read_file( $file, { binmode => ':raw' } );
            if ($stream =~/^Salted/i) { decrypt(\$stream, $KEY); }
            %$href = %{ thaw( $stream ) };
        }
        if ( (keys %$href) < 1 ) { %$href = ( 'Main' => { 'note'=>"" } ) }
    }

    sub save 
    {
        my ($href, $file) = @_;
        $IN->Mode(ENABLE_MOUSE_INPUT);
        my $stream = freeze($href);
        encrypt( \$stream, $KEY ) if ( defined $KEY );
        write_file( $file, { binmode => ":raw" }, $stream );
    }

    sub encrypt
    {
        my ($data_ref, $key) = @_;
        my $cipher = Crypt::CBC->new( -key => $key, -cipher => 'Blowfish' );
        #加密之前加一段头信息
        $$data_ref = "HEAD". $$data_ref;
        $$data_ref = $cipher->encrypt( $$data_ref );
    }

    sub decrypt
    {
        my ($data_ref, $key) = @_;
        my $cipher = Crypt::CBC->new( -key => $key, -cipher => 'Blowfish' );
        $$data_ref = $cipher->decrypt( $$data_ref );
        #解密之后判断信息头
        if ($$data_ref =~s/^HEAD//) {  }
        else
        { 
            $OUT->Cls();
            $OUT->Write("Wrong Key\n");
            exit;
        }
    }

    sub logfile 
    {
        state $i = 0;
        my $fname = ".\\log.txt";

        if ($i == 0) { write_file( $fname, shift ) } 
        else         { write_file( $fname, { append => 1 }, shift ) }
        $i++;
    }
}

1;