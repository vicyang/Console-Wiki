use utf8;
use strict;
no strict 'refs';
use feature 'state';
use Time::HiRes 'sleep';
use IO::Handle;
use Encode;
use Storable qw/freeze thaw/;
use File::Slurp;
use Win32::Console;
STDOUT->autoflush(1);

our $env_ref;
our $env_ref_name;
our ($MAX_COL, $MAX_LINE) = (120, 30);
our $MATRIX = $MAX_COL * $MAX_LINE;

our $IN = Win32::Console->new(STD_INPUT_HANDLE);
our $OUT= Win32::Console->new(STD_OUTPUT_HANDLE);
system("mode con cols=$MAX_COL");
$OUT->Window(1, 0, 0, 119, 29);

our $IN_DEFAULT = $IN->Mode();

our $File;
if ( defined $ARGV[0] and (-e $ARGV[0]) )
{
    $File = $ARGV[0];
    $File =~s/\\/\//g;
    $OUT->Title("Wiki $ARGV[0]");
}
else
{
    print "Target file Not exists! Will open default notes\n";
    $File = encode('gbk', ".\\Notes.db");
}

$OUT->Cursor(1, 1, 99, 1);  #这里设置了光标高度，后面就不需要再设置了。
                            #如果后面每次都指定了高度，则光标会闪烁频繁以至于移动时看不见

$IN->Mode(ENABLE_MOUSE_INPUT);
$OUT->FillAttr($FG_WHITE | $BG_CYAN, $MATRIX, 0, 0);  #背景填充，0, 0为起点

my %hash;
my @info;

=struct
    存储不同层次下的菜单列表信息
    @info = (
        {                  # ---> level 0
            "key1" => 
            {   x    =>value, 
                light=>bool, 
                str  =>keyname, 
                ref  =>self
                y    =>value,
                length => strlen
            },
            "key2" => {},
            "key3" => {},
        },

        {                  # ---> level 1
            "key1/name1" => {},
            "key1/name2" => {},
            ...
        },
    )
=cut

&load_data( \%hash, $File );

GO_BACK:
#首列
our @indent=(1);
@info=();
$indent[1] = &expand(\%hash, \%{$info[0]}, "", $indent[0]);  #first key=""

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

    if ($arr[0]==2) #arr[0] -> key or mouse, [1] -> mouse x, [2] -> mouse y
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
                    ClearLight( $info[$i]{$prev[$i]} );
                    $prev[$i]=$path;
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
                    #MARK_1 取消清理子键信息
                    #在调用菜单事件之前，清理子键信息
                    for my $clear ($j..$max_level) 
                    {
                        #undef %{$info[$clear]};
                    }

                    context_menu(
                        $indent[$j], $arr[2], $info[$i], $path, $i
                    );
                        #缩进        坐标     当前级$info 绝对路径
                }
            }
        }

        if ($inside > 0) 
        {
        }

        $OUT->Cursor($mx, $my);
    } 
    elsif ($arr[0]==1 and $arr[1]==1 and $arr[5]==27) 
    {
        &save(\%hash, $File);
        $OUT->Cls();
        exit;
    }
    elsif ($arr[0]==1 and $arr[1]==1 and lc(chr($arr[5])) eq 's') 
    {
        &save(\%hash, $File);
        wrong("", "save!");
    }
    elsif ($arr[0]==1 and $arr[1]==1 and lc(chr($arr[5])) eq 'q') 
    {
        $OUT->Cls();
        $OUT->Write("Exit with out save\n");
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
    foreach my $kid (sort keys %$ref)
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

    foreach ( @fold, @file) 
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

    my @detail;
    $tmpstr = join("\n", @{ $item_ref->{'note'} });
    if ($tmpstr=~/\t[^\t]+\t/) 
    {
        @detail = &tabformat( $item_ref->{'note'} );
        print join("\n", @detail);
    } else {
        print $tmpstr;
    }

    $IN->Mode($IN_DEFAULT);
    my $inp;
    while (1) 
    {
        sleep 0.1;
        @arr=$IN->Input();
        if ($arr[0]==1 and $arr[5]==27) {
            $IN->Mode($IN_MODE_RECORD);
            last;
        } elsif ($arr[0]==1 and $arr[3]==17) {  #control
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
    &ClearRect($cx, $MAX_COL, $cy, $MAX_LINE);

    my $i = 0;
    my $tmpstr;
    my $nn;
    my @detail;
    my @notes;

    if ( exists $info->{'self'}{'note'} ) 
    {
        @notes = @{ $info->{'self'}{'note'} };
    } 
    else 
    {
        @notes = ();
    }

    $tmpstr=join("\n", @notes );
    if ($tmpstr=~/\t[^\t]+\t/) 
    {
        @detail = tabformat( \@notes );
    }

    foreach ( @notes ) 
    {
        $i++;
        $nn=sprintf("%02d ",$i);
        if ($#detail < 0) {
            $tmpstr=$_;
            $tmpstr=~s/\t/ /g;
            $tmpstr=substr($nn . $tmpstr, 0, $col_area);
        } else {
            $tmpstr=substr($nn . $detail[$i-1], 0, $col_area);
        }
        $OUT->Cursor($cx, $cy);
        $OUT->Write( $tmpstr );
        $OUT->FillAttr($FG_YELLOW|$BG_CYAN, $col_area, $cx, $cy++);
        last if ($cy >= ($MAX_LINE-1));
    }
    
    if ($i==0) 
    {
        $OUT->Cursor($cx, $cy);
        $OUT->Write("There is nothing");
        $OUT->FillAttr($FG_YELLOW|$BG_CYAN, $col_area, $cx, $cy);
    }

    #循环：当鼠标移开时恢复原来的信息
    my ($x, $y, $len) = (
        $info->{'x'}, 
        $info->{'y'}, 
        $info->{'length'}
    );

    while (1) 
    {
        sleep 0.03;
        @arr=$IN->Input();
        if ($arr[0]==2)        #0 => key/mouse, 1 => x, 2 => y
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

FILL_CLEAR: {
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
        $$hash{light}=0;
    }

    sub ClearRect 
    {
        my ($left, $right, $top, $bottom) = @_;
        my $delta=$right-$left;
        foreach ($top..$bottom) {
            $OUT->FillChar(" ", $delta, $left, $_);
            $OUT->FillAttr($FG_WHITE | $BG_CYAN, $delta, $left, $_);
        }
    }

    sub ClearRect_byColor
    {
        my ($color, $left, $right, $top, $bottom) = @_;
        my $delta = $right - $left;
        foreach ($top .. $bottom) {
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
            '0_编辑' => 'edit_notes',
            '1_清除' => 'delete_notes',
            '2_+BANK' => 'BANK_to_notes',
            '3_+ID'   => 'ID_to_notes',
        },
        
        '3_新建' => {
            '1_Normal' => 'add_sub_item',
            '2_ID' => 'add_sub_item_ID',
            '3_Bank' => 'add_sub_item_BANK',
            '4_Date' => 'add_date_item',
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
                        ClearLight_menu( $menu_inf[$i]{$prev[$i]} );
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
    foreach my $kid (sort keys %$ref)
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

    foreach ( @fold, @file ) 
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

        $newkey = &lineInput();
        return 0 if ($newkey eq 'exit');

        if ( exists $parent_ref->{"$newkey"} ) 
        {
            wrong("", "key exists");
            return 0;   
        }

        $parent_ref->{"$newkey"} = {
            'note' => [], 
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

        $newkey = &lineInput();
        return 0 if ($newkey eq 'exit');

        $path=~/:([^:]+)$/;        #提取子键
        $last_key = $1;
        if ( exists $parent_ref->{$last_key}{$newkey} ) 
        {
            wrong("", "key exists");
            return 0;   
        }

        $parent_ref->{$last_key}{$newkey} = {
            'note'=>[],
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
            'note'=>[],
        };
        undef $prev[$lv];               #取消上一次高亮菜单的记录

        my $adjust;
        $adjust = ( $lv == 0 ? 0 : $INDENT );

        $indent[$lv+1] = 
            expand($parent_ref, $info[$lv], $path, $indent[$lv]+$adjust);
        goto GO_CONTINUE;
    }


    sub add_sub_item_BANK
    {
        our @prev;
        our @indent;
        my ($parent_ref, $path, $lv) = @_;
        my $newkey;
        my $last_key;

        $newkey = &lineInput();
        return 0 if ($newkey eq 'exit');

        $path=~/:([^:]+)$/;        #提取子键
        $last_key = $1;
        if ( exists $parent_ref->{$last_key}{$newkey} ) 
        {
            wrong("", "key exists");
            return 0;   
        }
        $parent_ref->{$last_key}{$newkey} = {
            'note' => [
                encode('gbk', " "x4 . " 开行点: "),
                encode('gbk', " "x4 . "   姓名: "),
                encode('gbk', " "x4 . "   卡号: "),
                encode('gbk', " "x4 . " 登录名: "),
                encode('gbk', " "x4 . "passkey: "),
                encode('gbk', " "x4 . "   code: "),
                encode('gbk', " "x4 . " USBKey: "),
                encode('gbk', " "x4 . "   mark: "),
                encode('gbk', " "x4 . "   date: "),
            ],
        };
        undef $prev[$lv];               #取消上一次高亮菜单的记录

        my $adjust;
        $adjust = ( $lv == 0 ? 0 : $INDENT );

        $indent[$lv+1] = 
            expand($parent_ref, $info[$lv], $path, $indent[$lv]+$adjust);
        goto GO_CONTINUE;
    }

    sub add_sub_item_ID
    {
        our @prev;
        our @indent;
        my ($parent_ref, $path, $lv) = @_;
        my $newkey;
        my $last_key;

        $newkey = &lineInput();
        return 0 if ($newkey eq 'exit');

        $path=~/:([^:]+)$/;        #提取子键
        $last_key = $1;
        if ( exists $parent_ref->{$last_key}{$newkey} ) 
        {
            wrong("", "key exists");
            return 0;   
        }
        $parent_ref->{$last_key}{$newkey} = {
            'note' => [
                            '  website: ',
                            '   E-mail: ',
              encode('gbk', '       ID: '),
              encode('gbk', '     昵称: '),
              encode('gbk', ' 密码提示: '),
              encode('gbk', '    问题1: '),
              encode('gbk', '    答案1: '),
              encode('gbk', '    问题2: '),
              encode('gbk', '    答案2: '),
              encode('gbk', '    其他 : '),
            ],
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

        $newkey = &lineInput();
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
        $parent_ref->{$1}{ $env_ref_name } = $env_ref;

        $adjust = ( $lv == 0 ? 0 : $INDENT );

        $indent[$lv+1] = 
            expand($parent_ref, $info[$lv], $path, $indent[$lv]+$adjust);
        
        goto GO_CONTINUE;
    }

    sub edit_notes 
    {
        our @prev;
        our @indent;
        my @arr;
        my ($parent_ref, $path, $lv) = @_;
        my $adjust;

        $path=~/:([^:]+)$/;        #提取子键
        if ( exists $parent_ref->{$1}{'note'} )
        {
            use File::Temp 'tempfile';
            my ($fh, $fname) = tempfile();
            print $fh join( "\r\n", @{$parent_ref->{$1}{'note'}} );
            $fh->close();
            no File::Temp;
            system("notepad $fname");
            open READ, "<:raw", $fname or warn "$!";

            @{$parent_ref->{$1}{'note'}} = <READ>;
            for my $i ( @{$parent_ref->{$1}{'note'}} ) 
            {
                $i=~s/\r\n$//;
            }
            
            close READ;
        }

        $adjust = ( $lv == 0 ? 0 : $INDENT );
        
        $indent[$lv+1] = 
            expand(
                $parent_ref, $info[$lv], $path, $indent[$lv]+$adjust
            );

        goto GO_CONTINUE;
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
            use File::Temp 'tempfile';
            my ($fh, $fname) = tempfile();
            print $fh join( "\r\n", @{$parent_ref->{$1}{'note'}} ),"\r\n";
            print $fh 
            (
                encode('gbk', " "x4 . " website: \r\n"),
                encode('gbk', " "x4 . "  E-mail: \r\n"),
                encode('gbk', " "x4 . "nickname: \r\n"),
                encode('gbk', " "x4 . "      ID: \r\n"),
                encode('gbk', " "x4 . "    code: \r\n"),
                encode('gbk', " "x4 . "   问题1: \r\n"),
                encode('gbk', " "x4 . "   答案1: \r\n"),
                encode('gbk', " "x4 . "   问题2: \r\n"),
                encode('gbk', " "x4 . "   答案2: \r\n"),
                encode('gbk', " "x4 . "    备注: \r\n"),
                encode('gbk', " "x4 . "    date: \r\n\r\n"),
            );

            $fh->close();
            no File::Temp;
            system("notepad $fname");
            open READ, "<:raw", $fname or warn "$!";

            @{$parent_ref->{$1}{'note'}} = <READ>;
            for my $i ( @{$parent_ref->{$1}{'note'}} ) 
            {
                $i=~s/\r\n$//;
            }
            
            close READ;
        }

        $adjust = ( $lv == 0 ? 0 : $INDENT );
        
        $indent[$lv+1] = 
            expand(
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
            use File::Temp 'tempfile';
            my ($fh, $fname) = tempfile();
            print $fh join( "\r\n", @{$parent_ref->{$1}{'note'}} ),"\r\n";
            print $fh 
            (
                encode('gbk', " "x4 . " 开行点: \r\n"),
                encode('gbk', " "x4 . "   姓名: \r\n"),
                encode('gbk', " "x4 . "   卡号: \r\n"),
                encode('gbk', " "x4 . " 登录名: \r\n"),
                encode('gbk', " "x4 . "passkey: \r\n"),
                encode('gbk', " "x4 . "   code: \r\n"),
                encode('gbk', " "x4 . " USBKey: \r\n"),
                encode('gbk', " "x4 . "   mark: \r\n"),
                encode('gbk', " "x4 . "   date: \r\n\r\n"),
            );

            $fh->close();
            no File::Temp;
            system("notepad $fname");
            open READ, "<:raw", $fname or warn "$!";

            @{$parent_ref->{$1}{'note'}} = <READ>;
            for my $i ( @{$parent_ref->{$1}{'note'}} ) 
            {
                $i=~s/\r\n$//;
            }
            
            close READ;
        }

        $adjust = ( $lv == 0 ? 0 : $INDENT );
        
        $indent[$lv+1] = 
            expand(
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
            $parent_ref->{$1}{'note'} = [];
        }

        $adjust = ( $lv == 0 ? 0 : $INDENT );

        $indent[$lv+1] = 
            expand($parent_ref, $info[$lv], $path, $indent[$lv]+$adjust);
        
        goto GO_CONTINUE;
    }
}

COMMAND: 
{
    sub lineInput 
    {
        our $IN_DEFAULT;
        my $line;
        my $inp;
        my $prompt;
        my $PREV_IN_MODE;
        my $PREV_RECT;

        $line=$MAX_LINE-4;
        $prompt="Command:";
        $PREV_RECT    = $OUT->ReadRect(0, $line-1, $MAX_COL, $line+1);
        $PREV_IN_MODE = $IN->Mode();
        $IN->Mode( $IN_DEFAULT );

        fill_line("-", $MAX_COL, $FG_YELLOW|$BG_CYAN, $line-1);
        fill_line("-", $MAX_COL, $FG_YELLOW|$BG_CYAN, $line+1);
        ClearRect(0, $MAX_COL, $line, $line);
        $OUT->Cursor(0, $line);
        $OUT->Write($prompt);
        $inp=<STDIN>;
        chomp $inp;

        #    如果IN->Mode没有设置为原始状态，<STDIN>将无法退出。
        # $IN句柄在未设置时<STDIN>还是能够通过ENTER键结束行输入的
        # 通过print $IN->Mode(); 得到原始 Mode 代码为183
        #恢复
        $IN->Mode($PREV_IN_MODE);
        $OUT->WriteRect($PREV_RECT, 0, $line-1, $MAX_COL, $line+1);
        return $inp;
    }

    sub linesInput 
    {
        our $IN_DEFAULT;
        my $line;
        my $inp;
        my $prompt;
        my $PREV_IN_MODE;
        my $PREV_RECT;
        my @arr;

        $line=$MAX_LINE-4;
        $prompt="INPUT:";
        $PREV_RECT    = $OUT->ReadRect(0, $line-1, $MAX_COL, $line+1);
        $PREV_IN_MODE = $IN->Mode();
        $IN->Mode( $IN_DEFAULT );

        while (1) {
            fill_line("-", $MAX_COL, $FG_YELLOW|$BG_CYAN, $line-1);
            fill_line("-", $MAX_COL, $FG_YELLOW|$BG_CYAN, $line+1);
            ClearRect(0, $MAX_COL, $line, $line);
            $OUT->Cursor(0, $line);
            $OUT->Write($prompt);
            $inp=<STDIN>;
            chomp $inp;
            if (lc($inp) ne "exit") {
                push(@arr, $inp);
            } else {
                last;
            }
        }
        #    如果IN->Mode没有设置为原始状态，<STDIN>将无法退出。
        # $IN句柄在未设置时<STDIN>还是能够通过ENTER键结束行输入的
        # 通过print $IN->Mode(); 得到原始 Mode 代码为183

        #恢复
        $IN->Mode($PREV_IN_MODE);
        $OUT->WriteRect($PREV_RECT, 0, $line-1, $MAX_COL, $line+1);
        return @arr;
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
        $prompt="Command:";
        $PREV_RECT    = $OUT->ReadRect(0, $line-1, $MAX_COL, $line+1);
        $PREV_IN_MODE = $IN->Mode();
        $IN->Mode( $IN_DEFAULT );

        while (1) 
        {
            $OUT->Cls();
            $tmpstr = join("\n", @{$item_ref->{'note'}} );
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

            $inp=<STDIN>;
            $inp=~s/\r?\n$//;
            last if (lc($inp) eq "exit");
            push( @{$item_ref->{'note'}}, $inp );
        }
        

        # MARK_2 待添加功能：命令处理： delete 编号、insert 编号、change 编号

        #    如果IN->Mode没有设置为原始状态，<STDIN>将无法退出。
        # $IN句柄在未设置时<STDIN>还是能够通过ENTER键结束行输入的
        # 通过print $IN->Mode(); 得到原始 Mode 代码为183

        #恢复
        $IN->Mode($PREV_IN_MODE);
        $OUT->WriteRect($PREV_RECT, 0, $line-1, $MAX_COL, $line+1);
        return $inp;
    }

    sub wrong 
    {
        my ($func_name, $func_say) = @_;
        $func_say = "Nothing" unless (defined $func_say);
        $OUT->Cursor(0, 0);
        $OUT->Write("$func_name say: $func_say");
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

        if ( $$hash{x} <= $mx 
             and $$hash{y} == $my 
             and ($$hash{length}+$$hash{x}) >= $mx )
             { return 1 } 
        else { return 0 }

        #本函数原来有个BUG，当使用一个空的hash调用的时候，
        #$hash{x} {y} {length}都为空，但是被作为0计算，当坐标刚好位于0,0 的时候，问题就出来了
    }

    sub inDetail 
    {
        my ( $hash, $mx, $my ) = @_;

        return 0 if (! defined $$hash{length});
        # (length-1, length)
        if (
            ($$hash{length}+$$hash{x}-1) <= $mx
                        and
            $mx < ($$hash{length}+$$hash{x}+1)
                        and
            $$hash{y} == $my
            )
        {
            return 1;
        } else {
            return 0;
        }
    }
}

LOAD_AND_SAVE:
{
    sub load_data
    {
        my ($href, $file) = @_;
        if ( -e $file ) 
        {
            my $stream = read_file( $file, binmode => ':raw' );
            %$href = %{ thaw( $stream ) };
        }
        if ( (keys %$href) < 1 ) { %$href = ( 'Main' => { 'note'=>[] } ) }
    }

    sub save 
    {
        my ($href, $file) = @_;
        $IN->Mode(ENABLE_MOUSE_INPUT);
        write_file( $file, { binmode=>":raw" }, freeze($href) );
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

ELSE_FUNCTION: 
{
    sub get_date 
    {
        my (
            $sec, $min, $hour,$mday, $mon, $year,$wday, $yday, $isdst
        ) = localtime( time() );
        return sprintf("%d-%02d-%02d", $year+1900, $mon+1, $mday);
    }
}
