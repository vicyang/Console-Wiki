use utf8;

sub context_menu 
{
    #调用注释
    #  ReadRect和WriteRect 的时候，指定的是区域坐标。采用$dtx
    #  ClearRect 和 FillAttr ，指定的是实际长度，所以用$col_area

    my @arr;
    my ($initx, $inity, $info, $path, $lv) = @_;
    my @menu;

    my @menu_inf = ();
    my $menus = 
    {
        '0_添加目录' => 'add_item',
        '1_重命名' => 'rename_item',
        '2_复制' => 'copy_tree',
        '3_粘贴' => 'paste_tree',
        '4_删除' => 'delete_item',

        '2_信息' => {
            '0_notepad'  => 'notepad',
            '1_Vim'      => 'vim',
            '2_清除'  => 'delete_notes',
            '3_+BANK' => 'BANK_to_notes',
            '4_+ID'   => 'ID_to_notes',
        },
        
        '3_新建' => {
            '0_Normal' => 'add_sub_item',
            '1_Date'   => 'add_date_item',
        },
    };

    #记录 并清理从左往右的区域
    my $PREV_RECT = $OUT->ReadRect(
            $initx, 1, $MAX_COL, $MAX_LINE
        );

    ClearRect($initx, $MAX_COL, 1, $MAX_LINE);

    my @prev;
    my @indent;
    my $j;
    my $max_level = 4;
    $indent[0] = $initx + 1;  #避免和原标签冲突（原标签预留2个字节位置用于显示概要）
    $indent[1] = 
        expand_menu($menus, \%{$menu_inf[0]}, "", $indent[0], $inity);  #显示菜单并记录菜单信息

    CONTEXT_WHILE: 
    while (1)
    {
        sleep 0.03;
        @arr = $IN->Input();
        next if $#arr < 0;

        my $inside = 0;
        if ($arr[0] == 2)   #鼠标操作
        {
            ($mx, $my) = ($arr[1], $arr[2]);
            
            for my $i (0..$max_level)     # 0,1,2代表列表的层次
            {
                $j = $i+1;
                for my $m_path (keys %{$menu_inf[$i]})   #这个$path是fullpath的
                {
                    #如果位于某个条目并且状态并非高亮 -> 切换到高亮并显示下一级条目

                    if (  inItem( $menu_inf[$i]{$m_path}, @arr[1,2] )) {
                        $inside++;

                        #单击鼠标左键且该选项指向一个函数
                        if ( $arr[3]==1 and defined $menu_inf[$i]{$m_path}->{'func'} ) 
                        {
                            &{ $menu_inf[$i]{$m_path}->{'func'} }(
                                $$info{$path}{'parent'}, $path, $lv
                            );
                            last CONTEXT_WHILE;
                        }
                    }

                    if (
                        inItem( $menu_inf[$i]{$m_path}, @arr[1,2] )
                                    and 
                            $menu_inf[$i]{$m_path}{light}==0  
                    )
                    {
                        #清理次级高亮条目 (首层的光标改变时), 放在expand之前执行，
                        if ( defined $prev[$j] ) 
                        {
                            #ClearLight_menu( $menu_inf[$j]{$prev[$j]} );
                            undef $prev[$j];
                            for my $clear ($j..$max_level) 
                            {
                                undef %{$menu_inf[$clear]};
                            }
                        }

                        $indent[$j+1] = 
                            expand_menu(
                                $menu_inf[$i]{$m_path}{'self'},   #当前对象
                                $menu_inf[$j],                    #设置下一级菜单
                                $m_path,                          #完整path
                                $indent[$j]+1,                    #缩进量
                                $my
                            );

                        #移除当前条目上一次的光标
                        ClearLight_menu( $menu_inf[$i]{$prev[$i]} ) if defined $prev[$i];
                        HighLightItem( $menu_inf[$i]{$m_path} );
                        $prev[$i]=$m_path;
                    }
                }
            }
        }
        #$OUT->Cursor( ($IN->Input())[1,2]);  #恢复光标位置

        #如果鼠标位置不在条目内，以及不在path条目位置，退出菜单循环
        if ($inside == 0 and ( not inItem( $$info{$path}, @arr[1,2])) )
        {
            last; # CONTEXT_WHILE;
        }
    }

    $OUT->WriteRect($PREV_RECT, $initx, 1, $MAX_COL, $MAX_LINE);

}

sub expand_menu 
{
    my ($ref, $info, $parent, $indent, $cy) = @_;
    my $cx = $indent;
    my $mark;
    my $max=0;
    my $len=0;
    my @fold;    #fold 和file的作用是含子菜单和不含子菜单的先后分开列出。避免混乱显示
    my @file;

    ClearRect($cx, $MAX_COL, 1, $MAX_LINE);  #从首行开始清理（0行留给提示信息）

    %$info=();
    my $tkid;
    for my $kid (sort keys %$ref)
    {
        next if ($kid eq 'note');

        $tkid = encode('gbk', $kid);
        $tkid =~s/\d_//;  #去掉编号信息
        $mark = $parent .":". $kid;
        
        
        if ( (keys %{$ref->{$kid}} ) > 0 )  #目录
        {
            $tkid = " $tkid ->";
            push @fold, $mark;
        } else {
            $tkid = " $tkid ";
            push @file, $mark;
        }

        $len = length($tkid);
        $max = $len if ( $len > $max );

        $$info{$mark} = {       # key name使用完整路径
            "x"     => $cx,     # 由于@fold和@file分开列出，所以$cy在后面排列时设置
            "light" => 0,       # 高亮状态
            "str"   => $tkid,   # 用于显示的keyname
            "self"  => $ref->{$kid},   # 该key的引用
            "parent"=> $ref,
        };

        if ( (keys %{$ref->{$kid}} ) == 0 )
        {
            $$info{$mark}{'func'} = \&{ $ref->{$kid} };
        }

    }

    for ( @fold, @file ) 
    {
        $$info{$_}{"y"} = $cy++;
        $$info{$_}{"length"} = $max;

        $OUT->Cursor($$info{$_}{x}, $$info{$_}{y});
        $OUT->Write($$info{$_}{str}."\b");

        $OUT->FillAttr(
            $FG_YELLOW|$BG_BLUE, 
            $$info{$_}{length}, 
            $$info{$_}{x}, 
            $$info{$_}{y}
        );
    }

    return $max+$indent;
}

MENU_FUNC: 
{
    sub add_item 
    {
        our @prev;
        our @indent;
        my ($parent_ref, $path, $lv) = @_;
        my $newkey;

        $newkey = lineInput();
        return 0 if ($newkey eq 'exit');

        if ( exists $parent_ref->{$newkey} ) 
        {
            wrong("", "key exists");
            return 0;   
        }

        $parent_ref->{$newkey} = {
            'note' => "",
        };
        undef $prev[$lv];               #取消上一次高亮菜单的记录

        my $adjust;
        $adjust = ( $lv == 0 ? 0 : $INDENT );

        $indent[$lv+1] = 
            expand($parent_ref, $info[$lv], $path, $indent[$lv]+$adjust);
        
        goto GO_CONTINUE;
    }

    sub add_sub_item
    {
        our @prev;
        our @indent;
        my ($parent_ref, $path, $lv) = @_;
        my $newkey;
        my $last_key;

        $newkey = lineInput();
        return 0 if ($newkey eq 'exit');

        $path=~/:([^:]+)$/;        #提取子键
        $last_key = $1;
        if ( exists $parent_ref->{$last_key}{$newkey} ) 
        {
            wrong("", "key exists");
            return 0;   
        }

        $parent_ref->{$last_key}{$newkey} = {
            'note' => "",
        };
        undef $prev[$lv];               #取消上一次高亮菜单的记录

        my $adjust;
        $adjust = ( $lv == 0 ? 0 : $INDENT );

        $indent[$lv+1] = 
            expand($parent_ref, $info[$lv], $path, $indent[$lv]+$adjust);
        goto GO_CONTINUE;
    }

    sub add_date_item
    {
        our @prev;
        our @indent;
        my ($parent_ref, $path, $lv) = @_;
        my $newkey;
        my $last_key;

        $newkey = get_date();

        $path=~/:([^:]+)$/;        #提取子键
        $last_key = $1;
        if ( exists $parent_ref->{$last_key}{$newkey} ) 
        {
            wrong("", "key exists");
            return 0;   
        }

        $parent_ref->{$last_key}{$newkey} = {
            'note' => "",
        };
        undef $prev[$lv];               #取消上一次高亮菜单的记录

        my $adjust;
        $adjust = ( $lv == 0 ? 0 : $INDENT );

        $indent[$lv+1] = 
            expand($parent_ref, $info[$lv], $path, $indent[$lv]+$adjust);
        goto GO_CONTINUE;
    }

    sub rename_item 
    {
        our @prev;
        our @indent;
        my ($parent_ref, $path, $lv) = @_;
        my $newkey;
        my $last_key;

        $newkey = lineInput();
        return 0 if ($newkey eq 'exit');

        $path=~/:([^:]+)$/;        #提取子键
        $last_key = $1;
        $parent_ref->{$newkey} = $parent_ref->{ $last_key };
        delete $parent_ref->{$last_key};

        undef $prev[$lv];               #取消上一次高亮菜单的记录

        my $adjust;
        $adjust = ( $lv == 0 ? 0 : $INDENT );

        $indent[$lv+1] = 
            expand($parent_ref, $info[$lv], $path, $indent[$lv]+$adjust);
        
        goto GO_CONTINUE;
    }

    sub delete_item 
    {
        our @prev;
        our @indent;
        my ($parent_ref, $path, $lv) = @_;
        my $adjust;

        $path=~/:([^:]+)$/;        #提取子键
        delete $parent_ref->{$1};

        $adjust = ( $lv == 0 ? 0 : $INDENT );

        $indent[$lv+1] = 
            expand($parent_ref, $info[$lv], $path, $indent[$lv]+$adjust);
        
        goto GO_CONTINUE;
    }

    sub copy_tree 
    {
        our @prev;
        our @indent;
        our $env_ref;
        our $env_ref_name;

        my ($parent_ref, $path, $lv) = @_;
        my $adjust;

        $path=~/:([^:]+)$/;
        $env_ref_name = $1;
        $env_ref = $parent_ref->{$1};
    }

    sub paste_tree
    {
        our @prev;
        our @indent;
        our $env_ref;
        our $env_ref_name;

        my ($parent_ref, $path, $lv) = @_;
        my $adjust;

        if (! defined $env_ref_name) 
        {
            wrong("paste_tree", "nothing in memory");
            return;
        }

        $path=~/:([^:]+)$/;        #提取子键
        if ( $env_ref_name eq $1 ) 
        {
            wrong("paste_tree", "Don't copy to same place!");
            return;
        }

        $parent_ref->{$1}{ $env_ref_name } = $env_ref;

        $adjust = ( $lv == 0 ? 0 : $INDENT );

        $indent[$lv+1] = 
            expand($parent_ref, $info[$lv], $path, $indent[$lv]+$adjust);
        
        goto GO_CONTINUE;
    }

    sub notepad
    {
        our @prev;
        our @indent;
        my @arr;
        my ($parent_ref, $path, $lv) = @_;
        my $adjust;

        $path=~/:([^:]+)$/;        #提取子键
        if ( exists $parent_ref->{$1}{'note'} )
        {
            #写入临时文件
            my ($fh, $fname) = tempfile();
            print $fh $BOM;
            print $fh $parent_ref->{$1}{'note'};
            $fh->close();

            #打开记事本编辑
            system("notepad $fname");

            #编辑完成后重新读入，删除BOM
            $parent_ref->{$1}{'note'} = read_file( $fname, { binmode => ":raw" } );
            $parent_ref->{$1}{'note'} =~s/^$BOM//;

            unlink $fname;
        }

        # $adjust = ( $lv == 0 ? 0 : $INDENT );        
        # $indent[$lv+1] = 
        #     expand(
        #         $parent_ref, $info[$lv], $path, $indent[$lv]+$adjust
        #     );
        #goto GO_CONTINUE;
    }

    sub vim
    {
        our @prev;
        our @indent;
        my @arr;
        my ($parent_ref, $path, $lv) = @_;
        my $adjust;
        my $PREV_RECT = $OUT->ReadRect(0, 0, $MAX_COL, $MAX_LINE);

        $path=~/:([^:]+)$/;        #提取子键
        if ( exists $parent_ref->{$1}{'note'} )
        {
            #写入临时文件
            my ($fh, $fname) = tempfile();
            print $fh $parent_ref->{$1}{'note'};
            $fh->close();
            
            my $vimcmd = 
                join("|", 
                    "set enc=utf-8",
                    "set fileencodings=utf-8,gbk",
                    "language messages zh_CN.utf-8",
                    "set smartindent",
                    "set tabstop=4",
                    "set shiftwidth=4",
                    "set expandtab",
                    "set softtabstop=4",
                    "set noswapfile",
                    "set nobackup",
                    "set noundofile"
                );

            #vim
            system("vim -c \"$vimcmd\" $fname");

            #编辑完成后重新读入
            $parent_ref->{$1}{'note'} = read_file( $fname, { binmode => ":raw" } );
            unlink $fname;
        }

        $OUT->WriteRect($PREV_RECT, 0, 0, $MAX_COL, $MAX_LINE);
        #调用vim之后鼠标无响应，重新开启
        $IN->Mode(ENABLE_MOUSE_INPUT);
    }

    sub ID_to_notes
    {
        our @prev;
        our @indent;
        my @arr;
        my ($parent_ref, $path, $lv) = @_;
        my $adjust;

        $path=~/:([^:]+)$/;        #提取子键
        if ( exists $parent_ref->{$1}{'note'} )
        {
            $parent_ref->{$1}{'note'} .=
                encode('utf8', join("\r\n",
                    " website: ",
                    "  E-mail: ",
                    "nickname: ",
                    "      ID: ",
                    "    code: ",
                    "   问题1: ",
                    "   答案1: ",
                    "   问题2: ",
                    "   答案2: ",
                    "    备注: ",
                    "    date: ", 
                    ""
                ));
        }

        $adjust = ( $lv == 0 ? 0 : $INDENT );
        
        $indent[$lv+1] = expand(
                $parent_ref, $info[$lv], $path, $indent[$lv]+$adjust
            );

        goto GO_CONTINUE;
    }

    sub BANK_to_notes
    {
        our @prev;
        our @indent;
        my @arr;
        my ($parent_ref, $path, $lv) = @_;
        my $adjust;

        $path=~/:([^:]+)$/;        #提取子键
        if ( exists $parent_ref->{$1}{'note'} ) 
        {
            $parent_ref->{$1}{'note'} .= 
                encode('utf8', join("\r\n",
                    " 开行点: ",
                    "   姓名: ",
                    "   卡号: ",
                    " 登录名: ",
                    "passkey: ",
                    "   code: ",
                    " USBKey: ",
                    "   mark: ",
                    "   date: ", 
                    ""
                ));
        }

        $adjust = ( $lv == 0 ? 0 : $INDENT );
        
        $indent[$lv+1] = expand(
                $parent_ref, $info[$lv], $path, $indent[$lv]+$adjust
            );

        goto GO_CONTINUE;
    }

    sub delete_notes 
    {
        our @prev;
        our @indent;
        my ($parent_ref, $path, $lv) = @_;
        my $adjust;

        $path=~/:([^:]+)$/;        #提取子键
        if ( exists $parent_ref->{$1}{'note'} ) 
        {
            $parent_ref->{$1}{'note'} = undef;
        }

        $adjust = ( $lv == 0 ? 0 : $INDENT );

        $indent[$lv+1] = 
            expand($parent_ref, $info[$lv], $path, $indent[$lv]+$adjust);
        
        goto GO_CONTINUE;
    }
}


1;