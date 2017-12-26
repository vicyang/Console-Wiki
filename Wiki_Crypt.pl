use warnings;
use utf8;
use feature     qw/state/;
use Time::HiRes qw/sleep time/;
use Encode      qw/from_to encode decode/;
use Storable    qw/freeze thaw/;
use Crypt::CBC;
use File::Slurp;
use File::Temp  qw/tempfile/;
use Win32::Console;

use IO::Handle;
STDOUT->autoflush(1);

INIT
{
    our $env_ref;
    our $env_ref_name;
    our ($MAX_COL, $MAX_LINE) = (120, 30);
    our $MATRIX = $MAX_COL * $MAX_LINE;
    our $BOM = "\xef\xbb\xbf";

    our $IN = Win32::Console->new(STD_INPUT_HANDLE);
    our $OUT= Win32::Console->new(STD_OUTPUT_HANDLE);
    our $IN_DEFAULT = $IN->Mode();

    system("mode con cols=$MAX_COL");
    $OUT->Window(1, 0, 0, 119, 29);
    
    #光标高度，若在循环中反复指定高度，则光标会闪烁频繁
    $OUT->Cursor(1, 1, 99, 1);  
    
    #默认文件
    our $File = "notes_crypt.db";
    our $KEY  = get_password();
}

if ( defined $ARGV[0] and (-e $ARGV[0]) )
{
    $File = $ARGV[0];
    $File =~s/\\/\//g;
}

$OUT->Title("Wiki - $File");

$IN->Mode(ENABLE_MOUSE_INPUT);

my %hash;
my @info;

load_data( \%hash, $File );
$OUT->FillAttr($FG_WHITE | $BG_CYAN, $MATRIX, 0, 0);  #背景填充，0, 0为起点

GO_BACK:
#首列
our @indent = (1);
@info = ();
$indent[1] = expand(\%hash, \%{$info[0]}, "", $indent[0]);  #first key=""

our @prev=();
our $INDENT = 2;   #统一缩进量

my ($mx, $my);
my $BackupRect;
my $max_level=6;
my $cur_level=0;

GO_CONTINUE: 
while (1) 
{
    sleep 0.02;
    my @arr = $IN->Input();
    my $inside;
    next if ( $#arr < 0 );

    if ( $arr[0] == 2 ) #arr[0] -> key or mouse, [1] -> mouse x, [2] -> mouse y
    {
        ($mx, $my) = ($arr[1], $arr[2]);
        $inside = 0;

        for my $i (0 .. $max_level)     # 0,1,2代表列表的层次
        {
            my $j = $i+1;
            for my $path (keys %{$info[$i]})   #这个$path是fullpath的
            {
                #如果位于某个条目并且状态并非高亮 -> 切换到高亮并显示下一级条目
                if ( inItem( $info[$i]{$path}, @arr[1,2]  ) )
                {
                    $inside++;
                }

                if (  inItem( $info[$i]{$path}, @arr[1,2] ) 
                                and 
                        $info[$i]{$path}{light}==0  )
                {
                    #加一句cursor 0,0 似乎能阻止条目高亮出现缺口
                    $OUT->Cursor(0,0);
                    HighLightItem( $info[$i]{$path} );

                    #清理次级高亮条目 (首层的光标改变时), 放在expand之前执行，
                    if (defined $prev[$j]) 
                    {
                        ClearLight( $info[$j]{$prev[$j]} );
                        undef $prev[$j];
                        for my $clear ($j..$max_level) 
                        {
                            undef %{$info[$clear]};
                        }
                    }

                    $indent[$j+1] = 
                        expand(
                            $info[$i]{$path}{'self'},   #当前对象
                            $info[$j],                  #设置下一级菜单
                            $path,                      #完整path
                            $indent[$j]+$INDENT         #缩进量
                        );

                    #移除当前条目上一次的光标
                    ClearLight( $info[$i]{$prev[$i]} ) if defined $prev[$i];
                    $prev[$i] = $path;
                }

                #显示信息摘要 
                if ( inDetail($info[$i]{$path}, @arr[1,2]) )
                {
                    show_info(
                        $info[$i]{$path},
                        $indent[$j]+$INDENT,
                        \$BackupRect
                    );
                }

                #单击鼠标左键时显示所有详细信息
                if ( inItem($info[$i]{$path}, @arr[1,2]) and $arr[3]==1 )
                {
                    show_detail( $info[$i]{$path}{'self'} );
                }

                #右键菜单
                if ( inItem($info[$i]{$path}, @arr[1,2]) and $arr[3]==2 )
                {
                    context_menu(
                        #缩进        坐标     当前级$info 绝对路径
                        $indent[$j], $arr[2], $info[$i], $path, $i
                    );
                }
            }
        }

        $OUT->Cursor($mx, $my);
    } 
    elsif ($arr[0]==1 and $arr[1]==1 and $arr[5]==27)
    {
        save(\%hash, $File);
        $OUT->Cls();
        exit;
    }
    elsif ($arr[0]==1 and $arr[1]==1 and lc(chr($arr[5])) eq 's') 
    {
        save(\%hash, $File);
        wrong("", "save!");
    }
    elsif ($arr[0]==1 and $arr[1]==1 and lc(chr($arr[5])) eq 'q') 
    {
        $OUT->Cls();
        $OUT->Write("Exit without saving\n");
        exit;
    }
    elsif ($arr[0]==1 and $arr[1]==1 and $arr[3]==116) #F5 刷新界面从头开始
    {
        $IN->Mode(ENABLE_MOUSE_INPUT);
        goto GO_BACK;
    }
}

sub expand
{
    my ($ref, $info, $parent, $indent) = @_;
    my ($cx, $cy) = ( $indent, 1 );
    ClearRect($cx, $MAX_COL, 1, $MAX_LINE);
    my $mark;
    my $max=0;
    my $len=0;
    my @fold;
    my @file;

    %$info=();
    my $tkid;
    for my $kid (sort keys %$ref)
    {
        next if ($kid eq 'note');     #跳过笔记标记
        $tkid = $kid;
        $mark = $parent .":". $kid;
        $tkid =~s/^\d_//;             #去掉编号信息
        
        if ( (keys %{$ref->{$kid}} ) > 1 ) 
        {
            $tkid = "/". $tkid;
            push @fold, $mark;
        } else {
            push @file, $mark;
        }

        $tkid = " $tkid ";
        $len = length($tkid);
        $max = $len if ( $len > $max );

        $$info{$mark} = {       # key name使用完整路径
            "x"     => $cx,     # 由于@fold和@file分开列出，所以$cy在后面排列时设置
            "light" => 0,       # 高亮状态
            "str"   => $tkid,   # 用于显示的keyname
            "self"  => $ref->{$kid},   # 该key的引用
            "parent"=> $ref,
        };
    }

    for ( @fold, @file ) 
    {    
        $$info{$_}{"y"} = $cy++;
        $$info{$_}{"length"} = $max;

        $OUT->Cursor($$info{$_}{x}, $$info{$_}{y});
        $OUT->Write($$info{$_}{str}); 
        $OUT->FillAttr(
            $FG_WHITE|$BG_CYAN, 
            $$info{$_}{length}, 
            $$info{$_}{x}, 
            $$info{$_}{y}
        );
    }
    return $max+$indent;
}

sub show_detail 
{
    our $IN;
    my $item_ref = shift;
    my @arr;
    my $BACKUP;
    my $IN_MODE_RECORD;
    my $tmpstr;
    $BACKUP = $OUT->ReadRect(1, 1, $MAX_COL, $MAX_LINE);
    $IN_MODE_RECORD = $IN->Mode();

	SHOW:
    $OUT->Cls();
    $OUT->Cursor(0,1);    #从第一行开始写信息

    $tmpstr = $item_ref->{'note'};
    from_to($tmpstr, 'utf8', 'gbk');
    print $tmpstr;

    $IN->Mode($IN_DEFAULT);
    my $inp;
    while (1) 
    {
        sleep 0.02;
        @arr = $IN->Input();
        next if $#arr < 0;
        if ($arr[0]==1 and $arr[5]==27) 
        {
            $IN->Mode($IN_MODE_RECORD);
            last;
        }
        elsif ($arr[0]==1 and $arr[3]==17) #control
        {
            $inp = inputBar( $item_ref );
            $IN->Mode($IN_MODE_RECORD);
            $OUT->Cursor(0, 0);
            goto SHOW;
        }
    }
    $OUT->Cls();
    $OUT->FillAttr($FG_WHITE | $BG_CYAN, $MATRIX, 0, 0);
    $OUT->WriteRect($BACKUP, 1, 1, $MAX_COL, $MAX_LINE);
}

sub show_info 
{
    my ($info, $indent, $PREV_RECT) = @_;
    my ($mx, $my);
    my @arr=();
    my $inity = 8;
    my ($cx, $cy)=($indent, $inity);
    my $col_area = $MAX_COL - $indent - 1;  #比最大边界少1

    my $line_area = $MAX_LINE - $cy;
    $PREV_RECT = $OUT->ReadRect($cx, $cy, $MAX_COL, $MAX_LINE);
    ClearRect($cx, $MAX_COL, $cy, $MAX_LINE);

    my $i = 0;
    my $tmpstr;
    my $nn;
    my @detail;
    my @notes;

    if ( exists $info->{'self'}{'note'} ) 
    { 
        $tmpstr = $info->{'self'}{'note'};
        from_to($tmpstr, 'utf8', 'gbk');
        @notes = split /\r?\n/, $tmpstr;
    }
    else { @notes = () }

    for ( @notes ) 
    {
        $i++;
        $nn = sprintf("%02d ", $i);
        $tmpstr = $_;
        $tmpstr =~s/\t/    /g;
        $tmpstr = substr($nn . $tmpstr, 0, $col_area);

        $OUT->Cursor($cx, $cy);
        $OUT->Write( $tmpstr );
        $OUT->FillAttr($FG_YELLOW|$BG_CYAN, $col_area, $cx, $cy++);
        last if ($cy >= ($MAX_LINE-1));
    }
    
    if ( $i == 0 )
    {
        $OUT->Cursor($cx, $cy);
        $OUT->Write("There is nothing");
        $OUT->FillAttr($FG_YELLOW|$BG_CYAN, $col_area, $cx, $cy);
    }

    #循环：当鼠标移开时恢复原来的信息
    my ($x, $y, $len) = @{$info}{'x', 'y', 'length'};

    while (1) 
    {
        sleep 0.03;
        @arr=$IN->Input();
        next if $#arr < 0;
        if ($arr[0] == 2)        #0 => key/mouse, 1 => x, 2 => y
        {   
            ($mx, $my) = ($arr[1], $arr[2]);
            $OUT->Cursor($mx, $my);
            if (not inDetail( $info, $mx, $my) )
            {
                $OUT->WriteRect($PREV_RECT, $cx, $inity, $MAX_COL, $MAX_LINE);
                last;
            }
        }
    }
}

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

CONTEXT_WHILE: while (1)
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
        encrypt( \$stream, $KEY );
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

OTHER_FUNCTION: 
{
    sub get_date 
    {
        my (
            $sec, $min, $hour,$mday, $mon, $year,$wday, $yday, $isdst
        ) = localtime( time() );
        return sprintf("%d-%02d-%02d", $year+1900, $mon+1, $mday);
    }
}
