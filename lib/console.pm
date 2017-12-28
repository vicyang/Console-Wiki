FILL_AND_CLEAR:
{
    sub ClearLight 
    {
        my $hash = shift;
        $OUT->FillAttr($FG_WHITE | $BG_CYAN, $$hash{length}, $$hash{x}, $$hash{y});
        $$hash{light}=0;
    }

    sub ClearLight_menu
    {
        my $hash = shift;
        $OUT->FillAttr($FG_YELLOW | $BG_BLUE, $$hash{length}, $$hash{x}, $$hash{y});
        $$hash{light} = 0;
    }

    sub ClearRect 
    {
        my ($left, $right, $top, $bottom) = @_;
        my $delta=$right-$left;
        for ($top..$bottom) {
            $OUT->FillChar(" ", $delta, $left, $_);
            $OUT->FillAttr($FG_WHITE | $BG_CYAN, $delta, $left, $_);
        }
    }

    sub ClearRect_byColor
    {
        my ($color, $left, $right, $top, $bottom) = @_;
        my $delta = $right - $left;
        for ($top .. $bottom) {
            $OUT->FillChar(" ", $delta, $left, $_);
            $OUT->FillAttr($color, $delta, $left, $_);
        }
    }

    sub fill_line 
    {
        my ($str, $length, $attr, $line) = @_;
        $OUT->FillChar($str, $length, 0, $line);
        $OUT->FillAttr($attr, $length, 0, $line);
    }

    sub HighLightItem
    {
        my $info_ref = shift;
        $OUT->FillAttr(
            $FG_BLACK | $BG_WHITE,
            $info_ref->{length},
            $info_ref->{x},
            $info_ref->{y}
        );
        $info_ref->{light}=1;
    }
}

IN_AREA: 
{
    sub inRange 
    {
        my ($a, $x, $b) = @_;
        if ($a<=$x and $b>=$x) { return 1 } 
        else                   { return 0 }
    }

    sub inRect 
    {
        my ( $x, $y, $left, $top, $right, $buttom ) = @_;
        if ( inRange($left, $x, $right) and inRange($top, $y, $buttom) ) 
             { return 1 } 
        else { return 0 }
    }

    sub inItem 
    {
        my ( $hash, $mx, $my ) = @_;
        return 0 if (! defined $$hash{length});

        if ( $$hash{x} <= $mx and 
             $$hash{y} == $my and 
             ($$hash{length}+$$hash{x}) >= $mx 
            ) { return 1 } 
        else  { return 0 }

        #本函数原来有个BUG，当使用一个空的hash调用的时候，
        #$hash{x} {y} {length}都为空，但是被作为0计算，当坐标刚好位于0,0 的时候，问题就出来了
    }

    sub inDetail 
    {
        my ( $hash, $mx, $my ) = @_;

        return 0 if (! defined $$hash{length});
        # (length-1, length)
        if ( ($$hash{length}+$$hash{x}-1) <= $mx
                        and
              $mx < ($$hash{length}+$$hash{x}+1)
                        and
              $$hash{y} == $my
           ) { return 1 } 
        else { return 0 }
    }
}

1;