COMMAND: 
{
    sub init_input_mode
    {
        our $IN_DEFAULT;
        my $line = $MAX_LINE - 5;
        fill_line("-", $MAX_COL, $FG_LIGHTGRAY|$BG_BLACK, $line-1);
        fill_line("-", $MAX_COL, $FG_LIGHTGRAY|$BG_BLACK, $line+1);
        $IN->Mode( $IN_DEFAULT );
    }

    sub get_password
    {
        my $inp;
        my $prompt;
        my $PREV_IN_MODE;
        my $PREV_RECT;

        my $line = $MAX_LINE - 5;
        $prompt = "Password:";
        $PREV_RECT    = $OUT->ReadRect(0, $line-1, $MAX_COL, $line+1);
        init_input_mode();

        $OUT->Cursor(0, $line);
        $OUT->Write($prompt);
        $inp = "";

        while (1)
        {
            sleep 0.01;
            @st = $IN->Input();
            next if ($#st < 0);
            if ( $st[0] == 1 and $st[1] == 1 )
            {
                if ( chr($st[5]) =~ /[\x20-\x7e]/ ) 
                { 
                    $OUT->Write("*");
                    $inp .= chr($st[5]);
                }
                elsif ( $st[5] == 27 ) { $OUT->Cls(); exit; }
                elsif ( $st[5] == 13 ) { last; }
                elsif ( $st[5] == 8 )  { 
                    if ( length($inp) > 0 ) 
                    {
                        $OUT->Write("\b \b");
                        $inp=~s/.$//;   
                    }
                }
            }
        }

        $OUT->WriteRect($PREV_RECT, 0, $line-1, $MAX_COL, $line+1);
        return $inp;
    }

    sub lineInput 
    {
        our $IN_DEFAULT;
        my $line;
        my $inp;
        my $prompt;
        my $PREV_IN_MODE;
        my $PREV_RECT;

        $line=$MAX_LINE-5;
        $prompt="Command:";
        $PREV_RECT    = $OUT->ReadRect(0, $line-1, $MAX_COL, $line+1);
        $PREV_IN_MODE = $IN->Mode();
        init_input_mode();

        ClearRect(0, $MAX_COL, $line, $line);
        $OUT->Cursor(0, $line);
        $OUT->Write($prompt);
        $inp=<STDIN>;
        chomp $inp;

        #    如果IN->Mode没有设置为原始状态，<STDIN>将无法退出。
        # $IN句柄在未设置时<STDIN>还是能够通过ENTER键结束行输入的
        # 通过print $IN->Mode(); 得到原始 Mode 代码为183
        # 恢复
        $IN->Mode($PREV_IN_MODE);
        $OUT->WriteRect($PREV_RECT, 0, $line-1, $MAX_COL, $line+1);
        return $inp;
    }

    sub inputBar 
    {
        our $IN_DEFAULT;
        my $item_ref = shift;
        my $line;
        my $inp;
        my $prompt;
        my $tmpstr;
        my $PREV_IN_MODE;
        my $PREV_RECT;

        $line = $MAX_LINE - 4;
        $prompt="Input:";
        $PREV_RECT    = $OUT->ReadRect(0, $line-1, $MAX_COL, $line+1);
        $PREV_IN_MODE = $IN->Mode();
        $IN->Mode( $IN_DEFAULT );

        while (1) 
        {
            $OUT->Cls();
            $tmpstr = encode('gbk', decode('utf8', $item_ref->{'note'} ));
            $OUT->Cursor(0, 1);
            $OUT->Write( $tmpstr );
            fill_line("-", $MAX_COL, $FG_YELLOW|$BG_BLACK, $line-1);
            fill_line("-", $MAX_COL, $FG_YELLOW|$BG_BLACK, $line+1);
            ClearRect(0, $MAX_COL, $line, $line);  #清理输入的行

            $OUT->Cursor(0, $line);                #回到行首
            $OUT->Write( $prompt );
            $OUT->FillAttr(
                $FG_YELLOW|$BG_BLACK, 
                $MAX_COL,
                0, 
                $line
            );

            $inp = <STDIN>;
            last if (lc($inp) eq "exit\n");
            $inp =~s/([^\r])\n/$1\r\n/gs;
            $item_ref->{'note'} .= $inp;
        }

        #恢复 STDIN
        $IN->Mode($PREV_IN_MODE);
        $OUT->WriteRect($PREV_RECT, 0, $line-1, $MAX_COL, $line+1);
        return $inp;
    }

    sub wrong 
    {
        my ($func_name, $func_say) = @_;
        $func_say = "Nothing" unless (defined $func_say);
        $OUT->Cursor(0, 0);
        $OUT->Write("$func_name: $func_say");
        $OUT->FillAttr($FG_YELLOW|$BG_CYAN, $MAX_COL-1, 0, 0);
    }
}

1;